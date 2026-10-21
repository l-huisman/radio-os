#!/usr/bin/env bats

setup() {
    TEST_ROOT=$(mktemp -d)
    export RADIO_HOME="$TEST_ROOT/radio"
    export RADIO_UPSTREAM="$TEST_ROOT/upstream"
    export RADIO_PATCHES_DIR="$TEST_ROOT/patches"
    export RADIO_BUILDER="$BATS_TEST_DIRNAME/fixtures/fake-builder"
    export RADIO_RESTART=true

    mkdir -p "$RADIO_PATCHES_DIR"
    git init -q -b main "$RADIO_UPSTREAM"
    git -C "$RADIO_UPSTREAM" config user.email test@example.com
    git -C "$RADIO_UPSTREAM" config user.name test
}

teardown() {
    rm -rf "$TEST_ROOT"
}

commit_upstream() {
    echo "$1" > "$RADIO_UPSTREAM/VERSION"
    git -C "$RADIO_UPSTREAM" add VERSION
    git -C "$RADIO_UPSTREAM" commit -q -m "$1"
    git -C "$RADIO_UPSTREAM" rev-parse HEAD
}

installed_version() {
    cat "$RADIO_HOME/current/build/am_stereo_receiver"
}

radio_update() {
    "$BATS_TEST_DIRNAME/../bin/radio-update" "$@"
}

@test "installs a pinned commit as the current build" {
    pinned=$(commit_upstream v1)
    commit_upstream v2

    run radio_update "$pinned"

    [ "$status" -eq 0 ]
    [ "$(installed_version)" = v1 ]
    [ ! -e "$RADIO_HOME/previous" ]
}

@test "without a commit it installs the latest upstream main" {
    commit_upstream v1
    commit_upstream v2

    run radio_update

    [ "$status" -eq 0 ]
    [ "$(installed_version)" = v2 ]
}

@test "an update keeps the old build as previous" {
    first=$(commit_upstream v1)
    radio_update "$first"
    commit_upstream v2

    run radio_update

    [ "$status" -eq 0 ]
    [ "$(installed_version)" = v2 ]
    [ "$(cat "$RADIO_HOME/previous/build/am_stereo_receiver")" = v1 ]
}

@test "a failed build leaves the current build in place" {
    first=$(commit_upstream v1)
    radio_update "$first"
    broken=$(commit_upstream v2)

    RADIO_BUILDER="$BATS_TEST_DIRNAME/fixtures/failing-builder" run radio_update

    [ "$status" -ne 0 ]
    [ "$(installed_version)" = v1 ]
    [ ! -e "$RADIO_HOME/builds/$broken" ]
}

@test "a patch that no longer applies aborts the update" {
    first=$(commit_upstream v1)
    radio_update "$first"
    commit_upstream v2
    cat > "$RADIO_PATCHES_DIR/0001-stale.patch" <<'EOF'
--- a/VERSION
+++ b/VERSION
@@ -1 +1 @@
-v1
+patched
EOF

    run radio_update

    [ "$status" -ne 0 ]
    [ "$(installed_version)" = v1 ]
}

@test "patches are applied to the source before building" {
    commit_upstream v1
    cat > "$RADIO_PATCHES_DIR/0001-mark.patch" <<'EOF'
--- a/VERSION
+++ b/VERSION
@@ -1 +1 @@
-v1
+v1-patched
EOF

    run radio_update

    [ "$status" -eq 0 ]
    [ "$(installed_version)" = v1-patched ]
}

@test "updating to the commit already installed changes nothing" {
    first=$(commit_upstream v1)
    radio_update "$first"
    before=$(readlink "$RADIO_HOME/current")

    run radio_update "$first"

    [ "$status" -eq 0 ]
    [ "$(readlink "$RADIO_HOME/current")" = "$before" ]
    [ ! -e "$RADIO_HOME/previous" ]
}

@test "rollback swaps the current and previous builds" {
    first=$(commit_upstream v1)
    radio_update "$first"
    commit_upstream v2
    radio_update

    run radio_update --rollback

    [ "$status" -eq 0 ]
    [ "$(installed_version)" = v1 ]
    [ "$(cat "$RADIO_HOME/previous/build/am_stereo_receiver")" = v2 ]
}

@test "rollback without a previous build fails and keeps the current one" {
    first=$(commit_upstream v1)
    radio_update "$first"

    run radio_update --rollback

    [ "$status" -ne 0 ]
    [ "$(installed_version)" = v1 ]
}

@test "only the current and previous builds are kept" {
    first=$(commit_upstream v1)
    radio_update "$first"
    commit_upstream v2
    radio_update
    commit_upstream v3
    radio_update

    run ls "$RADIO_HOME/builds"

    [ "${#lines[@]}" -eq 2 ]
    [ "$(installed_version)" = v3 ]
    [ "$(cat "$RADIO_HOME/previous/build/am_stereo_receiver")" = v2 ]
}

@test "the tuner is restarted after switching builds" {
    first=$(commit_upstream v1)
    export RADIO_RESTART="$TEST_ROOT/record-restart"
    printf '#!/bin/sh\ntouch "%s/restarted"\n' "$TEST_ROOT" > "$RADIO_RESTART"
    chmod +x "$RADIO_RESTART"

    run radio_update "$first"

    [ "$status" -eq 0 ]
    [ -e "$TEST_ROOT/restarted" ]
}

@test "status shows the current and previous commits" {
    first=$(commit_upstream v1)
    radio_update "$first"
    second=$(commit_upstream v2)
    radio_update

    run radio_update --status

    [ "$status" -eq 0 ]
    [[ "$output" == *"current:  $second"* ]]
    [[ "$output" == *"previous: $first"* ]]
}
