#!/usr/bin/env bash
# Turns a fresh Ubuntu Desktop 26.04 Raspberry Pi 4 into the radio.
# Run it from a terminal inside the desktop session, as the auto-login user.
# Safe to run again.
set -euo pipefail

radio_os_dir=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
lib=$radio_os_dir/lib/radio-os.sh
# shellcheck source=lib/radio-os.sh
source "$lib"

GITHUB_KEYS_URL=https://github.com/l-huisman.keys
RADIO_HOSTNAME=radio
BOOT_CONFIG=/boot/firmware/config.txt
TUNER_SETTINGS="$HOME/.config/TropicalRadioNetwork/AM Stereo Receiver.conf"

step() {
    printf '\n==> %s\n' "$*"
}

die() {
    echo "install.sh: $*" >&2
    exit 1
}

as_root() {
    sudo bash -c 'source "$1"; shift; "$@"' _ "$lib" "$@"
}

require_desktop_session() {
    [[ $EUID -ne 0 ]] || die "run this as the radio user, not as root"
    [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* && -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] ||
        die "run this from a terminal inside the GNOME desktop, not over SSH"
}

ask_secrets() {
    local confirm
    read -rp "Remote desktop username: " rdp_user
    read -rsp "Remote desktop password: " rdp_password && echo
    read -rsp "Remote desktop password again: " confirm && echo
    [[ -n "$rdp_user" && -n "$rdp_password" ]] || die "remote desktop username and password are required"
    [[ "$rdp_password" == "$confirm" ]] || die "the remote desktop passwords do not match"
    read -rsp "Login password of $USER (to empty the keyring): " login_password && echo
}

install_packages() {
    step "Installing packages"
    sudo apt-get update
    grep -v '^#' "$radio_os_dir/packages/build.txt" |
        xargs sudo apt-get install -y openssh-server alsa-utils
}

configure_hostname() {
    step "Setting the hostname to $RADIO_HOSTNAME"
    sudo hostnamectl set-hostname "$RADIO_HOSTNAME"
    if grep -q '^127\.0\.1\.1' /etc/hosts; then
        sudo sed -i "s/^127\.0\.1\.1\s.*/127.0.1.1\t$RADIO_HOSTNAME/" /etc/hosts
    else
        printf '127.0.1.1\t%s\n' "$RADIO_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
    fi
}

configure_audio() {
    step "Switching audio to the HiFiBerry DAC+ ADC"
    as_root configure_boot_audio "$BOOT_CONFIG"
    install -D -m 644 "$radio_os_dir/config/wireplumber-hifiberry.conf" \
        "$HOME/.config/wireplumber/wireplumber.conf.d/51-radio-os-hifiberry.conf"
}

configure_sdr_access() {
    step "Giving $USER access to the RTL-SDR dongle"
    sudo usermod -aG plugdev "$USER"
}

configure_autologin() {
    step "Logging $USER in automatically"
    as_root configure_gdm_autologin /etc/gdm3/custom.conf "$USER"
    printf '%s\n' "$login_password" | python3 -I "$radio_os_dir/lib/empty-keyring.py"
}

configure_screen() {
    step "Turning off screen lock, blanking and suspend"
    gsettings set org.gnome.desktop.screensaver lock-enabled false
    gsettings set org.gnome.desktop.session idle-delay 'uint32 0'
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
}

configure_remote_desktop() {
    step "Enabling remote desktop (screen sharing over RDP)"
    local tls_dir=$HOME/.local/share/gnome-remote-desktop
    mkdir -p "$tls_dir"
    if [[ ! -e "$tls_dir/tls.key" ]]; then
        openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
            -subj "/CN=$RADIO_HOSTNAME" -keyout "$tls_dir/tls.key" -out "$tls_dir/tls.crt"
    fi
    grdctl rdp set-tls-key "$tls_dir/tls.key"
    grdctl rdp set-tls-cert "$tls_dir/tls.crt"
    grdctl rdp set-credentials "$rdp_user" "$rdp_password"
    grdctl rdp disable-view-only
    grdctl rdp enable
    systemctl --user enable --now gnome-remote-desktop.service
}

configure_ssh() {
    step "Allowing SSH with the keys from $GITHUB_KEYS_URL only"
    local keys
    keys=$(mktemp)
    wget -qO "$keys" "$GITHUB_KEYS_URL"
    install -d -m 700 "$HOME/.ssh"
    merge_authorized_keys "$HOME/.ssh/authorized_keys" "$keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    rm -f "$keys"

    sudo install -m 644 "$radio_os_dir/config/sshd-radio-os.conf" /etc/ssh/sshd_config.d/50-radio-os.conf
    sudo sshd -t
    sudo systemctl try-restart ssh.service
}

configure_updates() {
    step "Security updates on, pop-ups off, weekly reboot Monday 04:00"
    sudo install -m 644 "$radio_os_dir/config/apt-unattended-upgrades.conf" /etc/apt/apt.conf.d/20auto-upgrades
    sudo sed -i 's/^Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades
    gsettings set com.ubuntu.update-notifier no-show-notifications true
    gsettings set com.ubuntu.update-notifier regular-auto-launch-interval 36500
    gsettings set com.ubuntu.update-notifier hide-reboot-notification true

    sudo install -m 644 "$radio_os_dir"/systemd/system/radio-os-weekly-reboot.* /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now radio-os-weekly-reboot.timer
}

install_tuner() {
    step "Building the tuner at the pinned commit"
    sudo ln -sfn "$radio_os_dir/bin/radio-update" /usr/local/bin/radio-update
    sudo ln -sfn "$radio_os_dir/bin/radio-health" /usr/local/bin/radio-health
    radio-update "$(cat "$radio_os_dir/tuner.commit")"
    seed_tuner_settings "$TUNER_SETTINGS"
}

install_launchers() {
    step "Starting the tuner at login and adding the Radio icon"
    install -D -m 644 "$radio_os_dir"/systemd/user/radio-os-* -t "$HOME/.config/systemd/user/"
    systemctl --user daemon-reload
    systemctl --user enable radio-os-tuner.service radio-os-health.timer

    install -D -m 644 "$radio_os_dir/desktop/radio-os-tuner.svg" \
        "$HOME/.local/share/icons/hicolor/scalable/apps/radio-os-tuner.svg"
    install -D -m 644 "$radio_os_dir/desktop/radio-os-tuner.desktop" \
        "$HOME/.local/share/applications/radio-os-tuner.desktop"
    gsettings set org.gnome.shell favorite-apps \
        "$(dock_favorites_with "$(gsettings get org.gnome.shell favorite-apps)" radio-os-tuner.desktop)"

    local desktop_dir
    desktop_dir=$(xdg-user-dir DESKTOP)
    install -D -m 755 "$radio_os_dir/desktop/radio-os-tuner.desktop" "$desktop_dir/radio-os-tuner.desktop"
    gio set "$desktop_dir/radio-os-tuner.desktop" metadata::trusted true || true
}

main() {
    require_desktop_session
    ask_secrets
    sudo -v

    install_packages
    configure_hostname
    configure_audio
    configure_sdr_access
    configure_autologin
    configure_screen
    configure_remote_desktop
    configure_ssh
    configure_updates
    install_tuner
    install_launchers

    step "Done"
    echo "Reboot to load the HiFiBerry driver and start the radio."
    read -rp "Reboot now? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]$ ]]; then
        sudo systemctl reboot
    fi
}

main "$@"
