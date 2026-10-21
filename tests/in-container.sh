#!/usr/bin/env bash
set -euo pipefail

echo "== shellcheck"
shellcheck --external-sources install.sh bin/* lib/*.sh tests/*.sh tests/fixtures/*

echo "== bats"
bats tests/

if [[ "${1:-}" == "--quick" ]]; then
    exit 0
fi

echo "== build the pinned tuner commit with the real patches"
export RADIO_HOME=/tmp/radio
export RADIO_RESTART=true
bin/radio-update "$(cat tuner.commit)"
binary="$RADIO_HOME/current/build/am_stereo_receiver"

echo "== check every shared library resolves"
if ldd "$binary" | grep 'not found'; then
    exit 1
fi

echo "== start the tuner headless and check it stays up"
# Without a sound card or SDR the tuner waits on a warning dialog, so stopping
# it with SIGTERM and saving settings is checked on the Pi (docs/acceptance.md).
export HOME=/tmp/home
mkdir -p "$HOME"
QT_QPA_PLATFORM=offscreen "$binary" > /tmp/tuner.log 2>&1 &
tuner=$!
sleep 5
if ! kill -0 "$tuner" 2> /dev/null; then
    echo "tuner exited during startup:" >&2
    cat /tmp/tuner.log >&2
    exit 1
fi
kill -KILL "$tuner"

echo "== all tests passed"
