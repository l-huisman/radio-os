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

## Install from a ready-made image (recommended)

No monitor needed. On a Mac or Linux machine with Docker on arm64:

```bash
image/build.sh
```

It downloads Ubuntu Desktop 26.04.1 for the Pi, asks for the `ellenam` login
password and the remote desktop username and password, and writes
`build/radio-os.img` (12 GB). Flash it with Raspberry Pi Imager (Use custom) to
a card of 16 GB or more, connect the HiFiBerry, the dongle and ethernet, and
power on. The first boot takes a few minutes and finishes the remote desktop
setup on its own.

## Install on a running Pi

1. Flash `ubuntu-26.04.1-preinstalled-desktop-arm64+raspi.img.xz` with Raspberry Pi Imager.
2. Boot the Pi with a monitor and ethernet and walk through the setup wizard:
   full name `EllenAM`, username `ellenam`, timezone Amsterdam.
3. Open a terminal and run:

   ```bash
   sudo apt install -y git
   git clone https://github.com/l-huisman/radio-os.git
   cd radio-os && ./install.sh
   ```

4. Reboot, then work through [docs/acceptance.md](docs/acceptance.md).

## Connecting

- Make the Pi's DHCP lease static on the MikroTik
  (IP > DHCP Server > Leases > Make Static) and connect to that address.
  `radio.local` is announced too, but not every computer resolves it.
- Windows: Remote Desktop Connection to the Pi's address. In a window,
  right-click the title bar and turn on Smart sizing.
- Mac: `sdl-freerdp /v:<address> /u:<user> /from-stdin:force /cert:ignore /smart-sizing /f`
  (`brew install freerdp`).

Remote desktop mirrors the Pi's screen, which is forced on at 1920x1080 so it
also works without a monitor. The client scales it, the Pi does not resize.

## What install.sh sets up

| Area | Setup |
|---|---|
| Audio | HiFiBerry overlay in `/boot/firmware/config.txt`, onboard and HDMI audio off, HiFiBerry preferred in WirePlumber |
| Tuner | Built from the commit in `tuner.commit` with the patches in `patches/`, under `~/.local/share/radio` |
| Start | `radio-os-tuner` user service: starts at login, restarts after a crash, stays closed when the window is closed. The Radio icon in the dock reopens it |
| First launch | 828 kHz, 9 kHz notch, stereo auto, 10 kHz bandwidth. Written only when the tuner has no settings yet |
| Login | GDM automatic login, login keyring with an empty password, no screen lock, blanking or suspend |
| Remote desktop | GNOME Desktop Sharing over RDP, mirrors the screen, with control. HDMI forced on at 1080p |
| SSH | Keys from `github.com/l-huisman.keys` only, no passwords |
| Updates | Security updates automatic, update and release pop-ups off, reboot every Monday at 04:00 (skipped in the first hour after boot, when the clock jumps) |
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
