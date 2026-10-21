#!/usr/bin/env bash
# System part of the radio setup. Runs as root, on a running Pi (install.sh) or
# inside the image chroot (image/chroot.sh). The radio user must already exist.
#
#   setup/system.sh <user>
set -euo pipefail

radio_os_dir=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
# shellcheck source=lib/radio-os.sh
source "$radio_os_dir/lib/radio-os.sh"

RADIO_USER=${1:?usage: setup/system.sh <user>}
RADIO_HOSTNAME=radio
GITHUB_KEYS_URL=https://github.com/l-huisman.keys
BOOT_CONFIG=/boot/firmware/config.txt
KERNEL_CMDLINE=/boot/firmware/current/cmdline.txt

step() {
    printf '\n==> %s\n' "$*"
}

user_home() {
    getent passwd "$RADIO_USER" | cut -d: -f6
}

install_packages() {
    step "Installing packages"
    apt-get update
    grep -v '^#' "$radio_os_dir/packages/build.txt" |
        xargs apt-get install -y openssh-server alsa-utils
}

configure_hostname() {
    step "Setting the hostname to $RADIO_HOSTNAME"
    echo "$RADIO_HOSTNAME" > /etc/hostname
    hostname "$RADIO_HOSTNAME" 2> /dev/null || true
    if grep -q '^127\.0\.1\.1' /etc/hosts; then
        sed -i "s/^127\.0\.1\.1\s.*/127.0.1.1\t$RADIO_HOSTNAME/" /etc/hosts
    else
        printf '127.0.1.1\t%s\n' "$RADIO_HOSTNAME" >> /etc/hosts
    fi
}

configure_audio() {
    step "Switching audio to the HiFiBerry DAC+ ADC"
    configure_boot_audio "$BOOT_CONFIG"
    install -D -m 644 "$radio_os_dir/config/wireplumber-hifiberry.conf" \
        /etc/wireplumber/wireplumber.conf.d/51-radio-os-hifiberry.conf
}

configure_display() {
    step "Keeping the HDMI output on without a monitor, for remote desktop"
    force_hdmi_output "$KERNEL_CMDLINE"
}

configure_sdr_access() {
    step "Giving $RADIO_USER access to the RTL-SDR dongle"
    usermod -aG plugdev "$RADIO_USER"
}

configure_autologin() {
    step "Logging $RADIO_USER in automatically"
    configure_gdm_autologin /etc/gdm3/custom.conf "$RADIO_USER"
}

configure_ssh() {
    step "Allowing SSH with the keys from $GITHUB_KEYS_URL only"
    local home keys
    home=$(user_home)
    keys=$(mktemp)
    wget -qO "$keys" "$GITHUB_KEYS_URL"
    install -d -m 700 -o "$RADIO_USER" -g "$RADIO_USER" "$home/.ssh"
    merge_authorized_keys "$home/.ssh/authorized_keys" "$keys"
    chown "$RADIO_USER:$RADIO_USER" "$home/.ssh/authorized_keys"
    chmod 600 "$home/.ssh/authorized_keys"
    rm -f "$keys"

    rm -f /etc/ssh/sshd_config.d/50-radio-os.conf
    install -m 644 "$radio_os_dir/config/sshd-10-radio-os.conf" /etc/ssh/sshd_config.d/10-radio-os.conf
    systemctl enable ssh.socket
    systemctl try-restart ssh.service
}

configure_updates() {
    step "Security updates on, release upgrade prompts off, weekly reboot Monday 04:00"
    install -m 644 "$radio_os_dir/config/apt-unattended-upgrades.conf" /etc/apt/apt.conf.d/20auto-upgrades
    sed -i 's/^Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades

    install -m 644 "$radio_os_dir"/systemd/system/radio-os-weekly-reboot.* /etc/systemd/system/
    systemctl enable radio-os-weekly-reboot.timer
}

install_commands() {
    step "Installing radio-update and radio-health"
    ln -sfn "$radio_os_dir/bin/radio-update" /usr/local/bin/radio-update
    ln -sfn "$radio_os_dir/bin/radio-health" /usr/local/bin/radio-health
}

install_packages
configure_hostname
configure_audio
configure_display
configure_sdr_access
configure_autologin
configure_ssh
configure_updates
install_commands
