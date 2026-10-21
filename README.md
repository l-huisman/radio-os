# radio-os

Sets up a Raspberry Pi 4 running Ubuntu Desktop 26.04 as a radio for the
[CQUAM AM Stereo Universal Tuner](https://github.com/VK4MTV/CQUAM-AM-Stereo-Universal-Tuner-for-GNUradio).
After setup the Pi logs in on its own, opens the tuner maximized on 828 kHz, and
can be controlled from a Windows PC over Remote Desktop.

## Hardware

- Raspberry Pi 4 (8 GB)
- HiFiBerry DAC+ ADC (HW 1.2), audio out through its RCA outputs
- RTL-SDR Blog V3 dongle
- HDMI monitor, keyboard, mouse, ethernet

## Install

1. Flash `ubuntu-26.04.1-preinstalled-desktop-arm64+raspi.img.xz` with Raspberry Pi Imager.
2. Boot the Pi with ethernet and walk through the setup wizard:
   full name `EllenAM`, username `ellenam`, timezone Amsterdam.
3. Open a terminal and run:

   ```bash
   sudo apt install -y git
   git clone https://github.com/l-huisman/radio-os.git
   cd radio-os && ./install.sh
   ```

   It asks for a remote desktop username and password, and for the login
   password (once, to empty the keyring). Building the tuner takes a few minutes.
4. Reboot, then work through [docs/acceptance.md](docs/acceptance.md).
5. On the MikroTik at the destination, make the Pi's DHCP lease static
   (IP > DHCP Server > Leases > Make Static). `radio.local` works as a fallback.

## What install.sh sets up

| Area | Setup |
|---|---|
| Audio | HiFiBerry overlay in `/boot/firmware/config.txt`, onboard and HDMI audio off, HiFiBerry preferred in WirePlumber |
| Tuner | Built from the commit in `tuner.commit` with the patches in `patches/`, under `~/.local/share/radio` |
| Start | `radio-os-tuner` user service: starts at login, restarts after a crash, stays closed when the window is closed. The Radio icon in the dock reopens it |
| First launch | 828 kHz, 9 kHz notch, stereo auto, 10 kHz bandwidth. Written only when the tuner has no settings yet |
| Login | GDM automatic login, login keyring with an empty password, no screen lock, blanking or suspend |
| Remote desktop | GNOME Desktop Sharing over RDP, mirrors the screen, with control |
| SSH | Keys from `github.com/l-huisman.keys` only, no passwords |
| Updates | Security updates automatic, update and release pop-ups off, reboot every Monday at 04:00 |
| Health | `radio-health` runs two minutes after login and logs what is missing |

## Updating the tuner

Over SSH (`ssh ellenam@radio.local`):

```bash
radio-update              # latest upstream main
radio-update <commit>     # a specific upstream commit
radio-update --rollback   # back to the previous build
radio-update --status     # current and previous commits
```

A new build is made next to the current one and only switched to when it
compiles and every patch applies. The previous build is kept for `--rollback`.
To move the pin for a fresh install, change `tuner.commit`.

## Patches

| Patch | Change |
|---|---|
| `0001-open-window-maximized` | Opens the tuner window maximized |
| `0002-save-settings-on-sigterm` | Saves the tuner settings when it is stopped by logout, reboot or `systemctl`, instead of only on a window close |

`0002` fixes upstream behaviour and is worth sending upstream as a PR.

## Logs

```bash
journalctl --user -u radio-os-health      # boot health check
journalctl --user -u radio-os-tuner       # tuner output and crashes
```

## Tests

```bash
tests/run.sh           # shellcheck, bats, real tuner build in an Ubuntu 26.04 arm64 container
tests/run.sh --quick   # without the tuner build
```

Needs Docker (on a Mac: `brew install docker colima && colima start`).
