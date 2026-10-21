#!/usr/bin/env bash
# User part of the radio setup: builds the tuner and sets up the desktop.
# Runs as the radio user with a D-Bus session bus, either in the desktop
# (install.sh) or under dbus-run-session in the image chroot (image/chroot.sh).
set -euo pipefail

radio_os_dir=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
# shellcheck source=lib/radio-os.sh
source "$radio_os_dir/lib/radio-os.sh"

TUNER_SETTINGS="$HOME/.config/TropicalRadioNetwork/AM Stereo Receiver.conf"
USER_UNITS=$HOME/.config/systemd/user

step() {
    printf '\n==> %s\n' "$*"
}

enable_user_unit() {
    local unit=$1 target=$2
    mkdir -p "$USER_UNITS/$target.wants"
    ln -sfn "$USER_UNITS/$unit" "$USER_UNITS/$target.wants/$unit"
}

install_tuner() {
    step "Building the tuner at the pinned commit"
    radio-update "$(cat "$radio_os_dir/tuner.commit")"
    seed_tuner_settings "$TUNER_SETTINGS"
}

install_launchers() {
    step "Starting the tuner at login and adding the Radio icon"
    install -D -m 644 -t "$USER_UNITS" "$radio_os_dir"/systemd/user/radio-os-*
    enable_user_unit radio-os-tuner.service graphical-session.target
    enable_user_unit radio-os-health.timer graphical-session.target
    systemctl --user daemon-reload 2> /dev/null || true

    install -D -m 644 "$radio_os_dir/desktop/radio-os-tuner.svg" \
        "$HOME/.local/share/icons/hicolor/scalable/apps/radio-os-tuner.svg"
    install -D -m 644 "$radio_os_dir/desktop/radio-os-tuner.desktop" \
        "$HOME/.local/share/applications/radio-os-tuner.desktop"
    gsettings set org.gnome.shell favorite-apps \
        "$(dock_favorites_with "$(gsettings get org.gnome.shell favorite-apps)" radio-os-tuner.desktop)"
}

configure_desktop() {
    step "Turning off screen lock, blanking, suspend, update pop-ups and the welcome tour"
    gsettings set org.gnome.desktop.screensaver lock-enabled false
    gsettings set org.gnome.desktop.session idle-delay 'uint32 0'
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
    gsettings set com.ubuntu.update-notifier no-show-notifications true
    gsettings set com.ubuntu.update-notifier regular-auto-launch-interval 36500
    gsettings set com.ubuntu.update-notifier hide-reboot-notification true

    mkdir -p "$HOME/.config"
    echo yes > "$HOME/.config/gnome-initial-setup-done"
}

install_tuner
install_launchers
configure_desktop
