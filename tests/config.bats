#!/usr/bin/env bats

setup() {
    TEST_ROOT=$(mktemp -d)
    # shellcheck source=../lib/radio-os.sh
    source "$BATS_TEST_DIRNAME/../lib/radio-os.sh"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

ubuntu_boot_config() {
    cp "$BATS_TEST_DIRNAME/fixtures/ubuntu-26.04/config.txt" "$TEST_ROOT/config.txt"
}

@test "boot config turns onboard audio off in place" {
    ubuntu_boot_config

    configure_boot_audio "$TEST_ROOT/config.txt"

    grep -qx 'dtparam=audio=off' "$TEST_ROOT/config.txt"
    ! grep -q 'dtparam=audio=on' "$TEST_ROOT/config.txt"
    [ "$(grep -n 'dtparam=audio=off' "$TEST_ROOT/config.txt" | cut -d: -f1)" -lt \
      "$(grep -n '^dtoverlay=vc4-kms-v3d' "$TEST_ROOT/config.txt" | head -n 1 | cut -d: -f1)" ]
}

@test "boot config turns HDMI audio off" {
    ubuntu_boot_config

    configure_boot_audio "$TEST_ROOT/config.txt"

    grep -qx 'dtoverlay=vc4-kms-v3d,noaudio' "$TEST_ROOT/config.txt"
}

@test "boot config loads the HiFiBerry DAC+ ADC overlay last, under [all]" {
    ubuntu_boot_config

    configure_boot_audio "$TEST_ROOT/config.txt"

    [ "$(tail -n 1 "$TEST_ROOT/config.txt")" = 'dtoverlay=hifiberry-dacplusadc' ]
    [ "$(grep -v '^#' "$TEST_ROOT/config.txt" | grep -v '^$' | tail -n 2 | head -n 1)" = '[all]' ]
}

@test "boot config changes are made only once" {
    ubuntu_boot_config
    configure_boot_audio "$TEST_ROOT/config.txt"
    cp "$TEST_ROOT/config.txt" "$TEST_ROOT/once.txt"

    configure_boot_audio "$TEST_ROOT/config.txt"

    diff "$TEST_ROOT/once.txt" "$TEST_ROOT/config.txt"
}

gdm_config() {
    cat > "$TEST_ROOT/custom.conf" <<'EOF'
# GDM configuration storage
#
# See /usr/share/gdm/gdm.schemas for a list of available options.

[daemon]
# Uncomment the line below to force the login screen to use Xorg
#WaylandEnable=false

# Enabling automatic login
#  AutomaticLoginEnable = true
#  AutomaticLogin = user1

[security]

[xdmcp]
EOF
}

@test "GDM automatic login is enabled for the user under [daemon]" {
    gdm_config

    configure_gdm_autologin "$TEST_ROOT/custom.conf" ellenam

    run awk '/^\[/{section=$0} /^AutomaticLogin/{print section ":" $0}' "$TEST_ROOT/custom.conf"
    [ "${lines[0]}" = '[daemon]:AutomaticLoginEnable=true' ]
    [ "${lines[1]}" = '[daemon]:AutomaticLogin=ellenam' ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "GDM automatic login replaces an earlier user" {
    gdm_config
    configure_gdm_autologin "$TEST_ROOT/custom.conf" someone

    configure_gdm_autologin "$TEST_ROOT/custom.conf" ellenam

    [ "$(grep -c '^AutomaticLogin=' "$TEST_ROOT/custom.conf")" -eq 1 ]
    grep -qx 'AutomaticLogin=ellenam' "$TEST_ROOT/custom.conf"
}

@test "GDM automatic login adds a [daemon] section when missing" {
    printf '[security]\n' > "$TEST_ROOT/custom.conf"

    configure_gdm_autologin "$TEST_ROOT/custom.conf" ellenam

    run awk '/^\[/{section=$0} /^AutomaticLogin/{print section ":" $0}' "$TEST_ROOT/custom.conf"
    [ "${lines[0]}" = '[daemon]:AutomaticLoginEnable=true' ]
    [ "${lines[1]}" = '[daemon]:AutomaticLogin=ellenam' ]
}

@test "tuner settings are seeded with 828 kHz and the 9 kHz notch" {
    settings="$TEST_ROOT/config/TropicalRadioNetwork/AM Stereo Receiver.conf"

    seed_tuner_settings "$settings"

    [ "$(cat "$settings")" = "$(printf '[radio]\nfrequency_khz=828\nnotch_mode=1\nstereo_mode=auto\naudio_bw_hz=10000')" ]
}

@test "existing tuner settings are never overwritten" {
    settings="$TEST_ROOT/AM Stereo Receiver.conf"
    printf '[radio]\nfrequency_khz=1008\n' > "$settings"

    seed_tuner_settings "$settings"

    [ "$(cat "$settings")" = "$(printf '[radio]\nfrequency_khz=1008')" ]
}

@test "new SSH keys are added once and existing keys are kept" {
    printf 'ssh-ed25519 AAAAexisting old@laptop\n' > "$TEST_ROOT/authorized_keys"
    printf 'ssh-ed25519 AAAAnew\nssh-ed25519 AAAAexisting\n' > "$TEST_ROOT/github.keys"

    merge_authorized_keys "$TEST_ROOT/authorized_keys" "$TEST_ROOT/github.keys"
    merge_authorized_keys "$TEST_ROOT/authorized_keys" "$TEST_ROOT/github.keys"

    [ "$(cat "$TEST_ROOT/authorized_keys")" = "$(printf 'ssh-ed25519 AAAAexisting old@laptop\nssh-ed25519 AAAAnew')" ]
}

@test "an empty key download is refused so SSH is never locked down without a key" {
    : > "$TEST_ROOT/github.keys"

    run merge_authorized_keys "$TEST_ROOT/authorized_keys" "$TEST_ROOT/github.keys"

    [ "$status" -ne 0 ]
}

@test "the tuner is added to the dock favourites once" {
    run dock_favorites_with "['org.gnome.Nautilus.desktop', 'firefox_firefox.desktop']" radio-os-tuner.desktop
    [ "$output" = "['org.gnome.Nautilus.desktop', 'firefox_firefox.desktop', 'radio-os-tuner.desktop']" ]

    run dock_favorites_with "$output" radio-os-tuner.desktop
    [ "$output" = "['org.gnome.Nautilus.desktop', 'firefox_firefox.desktop', 'radio-os-tuner.desktop']" ]

    run dock_favorites_with "@as []" radio-os-tuner.desktop
    [ "$output" = "['radio-os-tuner.desktop']" ]
}

@test "an empty-password login keyring is created as the default keyring" {
    write_empty_login_keyring "$TEST_ROOT/keyrings"

    [ "$(cat "$TEST_ROOT/keyrings/default")" = login ]
    grep -qx '\[keyring\]' "$TEST_ROOT/keyrings/login.keyring"
    grep -qx 'display-name=Login' "$TEST_ROOT/keyrings/login.keyring"
    grep -qx 'lock-on-idle=false' "$TEST_ROOT/keyrings/login.keyring"
    grep -qx 'lock-after=false' "$TEST_ROOT/keyrings/login.keyring"
    [ "$(stat -c %a "$TEST_ROOT/keyrings")" = 700 ]
    [ "$(stat -c %a "$TEST_ROOT/keyrings/login.keyring")" = 600 ]
}

@test "an existing login keyring is never replaced" {
    mkdir -p "$TEST_ROOT/keyrings"
    echo encrypted > "$TEST_ROOT/keyrings/login.keyring"

    run write_empty_login_keyring "$TEST_ROOT/keyrings"

    [ "$status" -ne 0 ]
    [ "$(cat "$TEST_ROOT/keyrings/login.keyring")" = encrypted ]
}

@test "GDM never starts the first-boot setup wizard" {
    gdm_config
    configure_gdm_autologin "$TEST_ROOT/custom.conf" ellenam

    configure_gdm_autologin "$TEST_ROOT/custom.conf" ellenam

    run awk '/^\[/{section=$0} /^InitialSetupEnable/{print section ":" $0}' "$TEST_ROOT/custom.conf"
    [ "$output" = '[daemon]:InitialSetupEnable=false' ]
}
