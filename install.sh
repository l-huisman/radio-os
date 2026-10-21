#!/usr/bin/env bash
# Turns a Raspberry Pi 4 with a freshly installed Ubuntu Desktop 26.04 into the
# radio. Run it from a terminal inside the desktop session, as the auto-login
# user. Safe to run again. For a ready-made SD card image, see image/build.sh.
set -euo pipefail

radio_os_dir=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)

die() {
    echo "install.sh: $*" >&2
    exit 1
}

require_desktop_session() {
    [[ $EUID -ne 0 ]] || die "run this as the radio user, not as root"
    [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* && -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] ||
        die "run this from a terminal inside the GNOME desktop, not over SSH"
}

ask_secrets() {
    local confirm
    read -rp "Remote desktop username: " RDP_USER
    read -rsp "Remote desktop password: " RDP_PASSWORD && echo
    read -rsp "Remote desktop password again: " confirm && echo
    [[ -n "$RDP_USER" && -n "$RDP_PASSWORD" ]] || die "remote desktop username and password are required"
    [[ "$RDP_PASSWORD" == "$confirm" ]] || die "the remote desktop passwords do not match"
    read -rsp "Login password of $USER (to empty the keyring): " login_password && echo
    export RDP_USER RDP_PASSWORD
}

main() {
    require_desktop_session
    ask_secrets

    sudo "$radio_os_dir/setup/system.sh" "$USER"
    printf '%s\n' "$login_password" | python3 -I "$radio_os_dir/lib/empty-keyring.py"
    "$radio_os_dir/setup/user.sh"
    "$radio_os_dir/setup/session.sh"

    printf '\n==> Done\n'
    echo "Reboot to load the HiFiBerry driver and start the radio."
    read -rp "Reboot now? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]$ ]]; then
        sudo systemctl reboot
    fi
}

main "$@"
