# shellcheck shell=bash
# Config-file edits used by install.sh. Each function only touches the file it
# is given and can be run any number of times.

# Turns off the Pi's onboard and HDMI audio and loads the HiFiBerry DAC+ ADC.
configure_boot_audio() {
    local config=$1

    sed -i \
        -e 's/^dtparam=audio=on$/dtparam=audio=off/' \
        -e 's/^\(dtoverlay=vc4-kms-v3d\)$/\1,noaudio/' \
        "$config"

    if ! grep -qx 'dtoverlay=hifiberry-dacplusadc' "$config"; then
        printf '\n[all]\n# radio-os: HiFiBerry DAC+ ADC\ndtoverlay=hifiberry-dacplusadc\n' >> "$config"
    fi
}

# Forces the first HDMI port on at 1080p, so the desktop (and remote desktop,
# which mirrors it) has a screen even when no monitor is connected.
force_hdmi_output() {
    local cmdline=$1

    sed -i -e 's/ *video=HDMI-A-1:[^ ]*//' -e 's/$/ video=HDMI-A-1:1920x1080@60D/' "$cmdline"
}

# Applies force_hdmi_output to the boot options of the running kernel and, when
# an update has staged one, of the next kernel.
force_hdmi_output_on_boot_assets() {
    local firmware=$1 assets

    for assets in current new; do
        if [[ -e "$firmware/$assets/cmdline.txt" ]]; then
            force_hdmi_output "$firmware/$assets/cmdline.txt"
        fi
    done
}

configure_gdm_autologin() {
    local config=$1 user=$2

    sed -i -e '/^AutomaticLoginEnable=/d' -e '/^AutomaticLogin=/d' -e '/^InitialSetupEnable=/d' "$config"

    if ! grep -qx '\[daemon\]' "$config"; then
        printf '\n[daemon]\n' >> "$config"
    fi

    sed -i "/^\[daemon\]\$/a AutomaticLoginEnable=true\nAutomaticLogin=$user\nInitialSetupEnable=false" "$config"
}

# Creates a login keyring without a password. gnome-keyring keeps such a keyring
# as plain text and opens it unlocked, also after an automatic login.
write_empty_login_keyring() {
    local keyrings=$1

    if [[ -e "$keyrings/login.keyring" ]]; then
        echo "$keyrings/login.keyring already exists" >&2
        return 1
    fi

    install -d -m 700 "$keyrings"
    printf '[keyring]\ndisplay-name=Login\nctime=0\nmtime=0\nlock-on-idle=false\nlock-after=false\n' \
        > "$keyrings/login.keyring"
    chmod 600 "$keyrings/login.keyring"
    echo login > "$keyrings/default"
}

# Writes the first-launch tuner settings, unless the tuner has saved its own.
seed_tuner_settings() {
    local settings=$1

    [[ -e "$settings" ]] && return 0

    mkdir -p "$(dirname "$settings")"
    printf '[radio]\nfrequency_khz=828\nnotch_mode=1\nstereo_mode=auto\naudio_bw_hz=10000\n' > "$settings"
}

merge_authorized_keys() {
    local authorized_keys=$1 new_keys=$2
    local key

    if ! grep -q '^ssh-' "$new_keys"; then
        echo "no SSH keys found in $new_keys" >&2
        return 1
    fi

    touch "$authorized_keys"
    while read -r key; do
        [[ "$key" == ssh-* ]] || continue
        if ! cut -d' ' -f2 "$authorized_keys" | grep -qxF "$(cut -d' ' -f2 <<< "$key")"; then
            echo "$key" >> "$authorized_keys"
        fi
    done < "$new_keys"
}

# Prints the gsettings favorite-apps value with the given app appended once.
dock_favorites_with() {
    local favorites=$1 app=$2

    python3 -I -c '
import ast, sys
favorites = sys.argv[1].removeprefix("@as ")
apps = ast.literal_eval(favorites)
if sys.argv[2] not in apps:
    apps.append(sys.argv[2])
print(apps)
' "$favorites" "$app"
}
