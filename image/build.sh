#!/usr/bin/env bash
# Builds a ready-to-flash SD card image of the radio: Ubuntu Desktop 26.04.1
# for the Raspberry Pi with everything from install.sh already done.
# Runs on a Mac or Linux machine with Docker on arm64. Result: build/radio-os.img
# Asks for the passwords, unless RADIO_USER_PASSWORD, RDP_USER and RDP_PASSWORD are set.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
UBUNTU_RELEASE_URL=https://cdimage.ubuntu.com/releases/26.04/release
UBUNTU_IMAGE=ubuntu-26.04.1-preinstalled-desktop-arm64+raspi.img.xz

die() {
    echo "build.sh: $*" >&2
    exit 1
}

ask_password() {
    local prompt=$1 password confirm
    read -rsp "$prompt: " password && echo >&2
    read -rsp "$prompt again: " confirm && echo >&2
    [[ -n "$password" ]] || die "the password cannot be empty"
    [[ "$password" == "$confirm" ]] || die "the passwords do not match"
    printf '%s' "$password"
}

download_ubuntu() {
    mkdir -p "$root/build"
    cd "$root/build"
    if [[ ! -e "$UBUNTU_IMAGE" ]]; then
        curl -fL -o "$UBUNTU_IMAGE.partial" "$UBUNTU_RELEASE_URL/$UBUNTU_IMAGE"
        mv "$UBUNTU_IMAGE.partial" "$UBUNTU_IMAGE"
    fi
    curl -fsSL -o SHA256SUMS "$UBUNTU_RELEASE_URL/SHA256SUMS"
    local expected actual
    expected=$(grep " \*$UBUNTU_IMAGE\$" SHA256SUMS | cut -d' ' -f1)
    actual=$(shasum -a 256 "$UBUNTU_IMAGE" 2> /dev/null || sha256sum "$UBUNTU_IMAGE")
    [[ "${actual%% *}" == "$expected" ]] || die "checksum of $UBUNTU_IMAGE does not match, delete it and retry"
}

[[ "$(docker version --format '{{.Server.Arch}}')" == arm64 ]] || die "Docker must run arm64 containers natively"

download_ubuntu
if [[ -z "${RADIO_USER_PASSWORD:-}" ]]; then
    RADIO_USER_PASSWORD=$(ask_password "Login password for ellenam")
fi
if [[ -z "${RDP_USER:-}" ]]; then
    read -rp "Remote desktop username: " RDP_USER
fi
[[ -n "$RDP_USER" ]] || die "the remote desktop username cannot be empty"
if [[ -z "${RDP_PASSWORD:-}" ]]; then
    RDP_PASSWORD=$(ask_password "Remote desktop password")
fi
export RADIO_USER_PASSWORD RDP_USER RDP_PASSWORD

docker run --rm --privileged \
    --volume "$root:/radio-os:ro" \
    --volume "$root/build:/work" \
    --env RADIO_USER_PASSWORD --env RDP_USER --env RDP_PASSWORD \
    --env UBUNTU_IMAGE="$UBUNTU_IMAGE" \
    ubuntu:26.04 /radio-os/image/customize.sh

echo
echo "Done: $root/build/radio-os.img"
echo "Flash it with Raspberry Pi Imager: Choose OS > Use custom."
