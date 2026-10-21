# Acceptance checklist

Run through this on the Pi after `install.sh` and the first reboot.

## Boot and tuner

- [ ] The Pi logs in to the desktop without a password prompt.
- [ ] The tuner opens maximized, tuned to 828 kHz, with the 9 kHz notch selected.
- [ ] The device label shows the RTL-SDR, and Ellen AM is audible.
- [ ] Sound comes from the HiFiBerry RCA outputs. `aplay -l` lists a `sndrpihifiberry` card and no `bcm2835` headphones card.
- [ ] After a reboot, `amixer -c sndrpihifiberry sget Digital` still shows 100% and `wpctl get-volume @DEFAULT_AUDIO_SINK@` shows 1.00.
- [ ] `journalctl --user -u radio-os-health` shows `radio is healthy` about two minutes after login.

## Restart behaviour

- [ ] Change the frequency, then run `systemctl --user restart radio-os-tuner`. The tuner comes back on the new frequency. (This checks patch 0002.)
- [ ] `pkill -SEGV am_stereo_receiver` makes the tuner come back within a few seconds.
- [ ] Closing the window keeps it closed. The Radio icon in the dock opens it again.

## Remote desktop

- [ ] From the Windows PC, Remote Desktop Connection to the Pi's IP shows the tuner and allows control.
- [ ] Same with `radio.local`.
- [ ] After `sudo reboot`, remote desktop still connects without anyone logging in on the Pi.

## SSH

- [ ] `ssh ellenam@radio.local` works with your key.
- [ ] `ssh -o PubkeyAuthentication=no ellenam@radio.local` is refused.

## Updates and reboot

- [ ] `systemctl list-timers radio-os-weekly-reboot.timer` shows the next run on Monday at 04:00.
- [ ] `radio-update --status` shows the pinned commit as current.
