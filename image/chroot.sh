#!/usr/bin/env bash
# Runs as root inside the mounted Ubuntu image (see image/customize.sh). Does
# what the setup wizard and install.sh do on a running Pi. The remote desktop
# part needs a live desktop, so it is left to a one-time job at the first login.
set -euo pipefail

RADIO_USER=ellenam
RADIO_FULL_NAME=EllenAM
RADIO_LANG=nl_NL.UTF-8
RADIO_TIMEZONE=Europe/Amsterdam
RADIO_KEYBOARD_VARIANT=altgr-intl
source_dir=/tmp/radio-os

export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8

home=/home/$RADIO_USER
radio_os_dir=$home/radio-os

step() {
    printf '\n==> %s\n' "$*"
}

as_user() {
    runuser -u "$RADIO_USER" -- env HOME="$home" USER="$RADIO_USER" LOGNAME="$RADIO_USER" \
        PATH=/usr/local/bin:/usr/bin:/bin "$@"
}

create_user() {
    step "Creating $RADIO_USER"
    local groups=() group
    for group in adm cdrom sudo dip plugdev lpadmin users; do
        getent group "$group" > /dev/null && groups+=("$group")
    done
    if ! id "$RADIO_USER" &> /dev/null; then
        useradd --create-home --shell /bin/bash --comment "$RADIO_FULL_NAME" \
            --groups "$(IFS=,; echo "${groups[*]}")" "$RADIO_USER"
    fi
    echo "$RADIO_USER:$RADIO_USER_PASSWORD" | chpasswd

    install -d -m 700 /var/lib/AccountsService/users
    printf '[User]\nLanguage=%s\nSession=ubuntu\nSystemAccount=false\n' "$RADIO_LANG" \
        > "/var/lib/AccountsService/users/$RADIO_USER"
}

configure_region() {
    step "Dutch language, $RADIO_TIMEZONE, US keyboard ($RADIO_KEYBOARD_VARIANT)"
    apt-get update
    apt-get install -y language-pack-nl language-pack-gnome-nl
    update-locale LANG="$RADIO_LANG"
    ln -sfn "/usr/share/zoneinfo/$RADIO_TIMEZONE" /etc/localtime
    echo "$RADIO_TIMEZONE" > /etc/timezone
    sed -i -e 's/^XKBLAYOUT=.*/XKBLAYOUT="us"/' -e "s/^XKBVARIANT=.*/XKBVARIANT=\"$RADIO_KEYBOARD_VARIANT\"/" \
        /etc/default/keyboard
}

keep_hostname_on_first_boot() {
    printf 'preserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99-radio-os.cfg
}

install_radio_os() {
    step "Copying radio-os to $radio_os_dir"
    rm -rf "$radio_os_dir"
    cp -a "$source_dir" "$radio_os_dir"
    chown -R "$RADIO_USER:$RADIO_USER" "$radio_os_dir"
}

prepare_first_login() {
    step "Preparing the first login"
    as_user bash -c "source '$radio_os_dir/lib/radio-os.sh' && write_empty_login_keyring '$home/.local/share/keyrings'"

    as_user install -d -m 700 "$home/.config/radio-os"
    # shellcheck disable=SC2016
    as_user bash -c 'umask 077 && printf "RDP_USER=%q\nRDP_PASSWORD=%q\n" "$1" "$2" > "$3"' \
        _ "$RDP_USER" "$RDP_PASSWORD" "$home/.config/radio-os/firstboot.env"

    local wants=$home/.config/systemd/user/graphical-session.target.wants
    as_user mkdir -p "$wants"
    as_user ln -sfn "$home/.config/systemd/user/radio-os-firstboot.service" "$wants/radio-os-firstboot.service"
}

: "${RADIO_USER_PASSWORD:?}" "${RDP_USER:?}" "${RDP_PASSWORD:?}"

create_user
configure_region
keep_hostname_on_first_boot
install_radio_os
"$radio_os_dir/setup/system.sh" "$RADIO_USER"

step "Building the tuner and setting up the desktop for $RADIO_USER"
as_user dbus-run-session -- bash -c "
    set -euo pipefail
    '$radio_os_dir/setup/user.sh'
    gsettings set org.gnome.desktop.input-sources sources \"[('xkb', 'us+$RADIO_KEYBOARD_VARIANT')]\"
"
prepare_first_login

apt-get clean
step "Image setup finished"
