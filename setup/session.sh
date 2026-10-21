#!/usr/bin/env bash
# Desktop-session part of the radio setup: remote desktop and the desktop icon.
# Needs the running GNOME session with an unlocked login keyring.
#
#   RDP_USER=... RDP_PASSWORD=... setup/session.sh
#   setup/session.sh --firstboot   reads ~/.config/radio-os/firstboot.env,
#                                  then deletes it and disables itself
set -euo pipefail

FIRSTBOOT_ENV=$HOME/.config/radio-os/firstboot.env

step() {
    printf '\n==> %s\n' "$*"
}

configure_remote_desktop() {
    step "Enabling remote desktop (screen sharing over RDP)"
    local tls_dir=$HOME/.local/share/gnome-remote-desktop
    mkdir -p "$tls_dir"
    if [[ ! -e "$tls_dir/tls.key" ]]; then
        openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
            -subj "/CN=$(hostname)" -keyout "$tls_dir/tls.key" -out "$tls_dir/tls.crt"
    fi
    grdctl rdp set-tls-key "$tls_dir/tls.key"
    grdctl rdp set-tls-cert "$tls_dir/tls.crt"
    grdctl rdp set-credentials "$RDP_USER" "$RDP_PASSWORD"
    grdctl rdp disable-view-only
    grdctl rdp enable
    systemctl --user enable --now gnome-remote-desktop.service
}

trust_desktop_icon() {
    local desktop_dir
    desktop_dir=$(xdg-user-dir DESKTOP)
    install -D -m 755 "$HOME/.local/share/applications/radio-os-tuner.desktop" \
        "$desktop_dir/radio-os-tuner.desktop"
    gio set "$desktop_dir/radio-os-tuner.desktop" metadata::trusted true || true
}

if [[ "${1:-}" == "--firstboot" ]]; then
    # shellcheck source=/dev/null
    source "$FIRSTBOOT_ENV"
fi

: "${RDP_USER:?RDP_USER is not set}" "${RDP_PASSWORD:?RDP_PASSWORD is not set}"

configure_remote_desktop
trust_desktop_icon

if [[ "${1:-}" == "--firstboot" ]]; then
    rm -f "$FIRSTBOOT_ENV"
    systemctl --user disable radio-os-firstboot.service
    systemctl --user start radio-os-tuner.service
    echo "first-boot setup finished"
fi
