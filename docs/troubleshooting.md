# Troubleshooting

**What:** Symptom → check for the failures that actually happen.
**Where:** this page.
**Verified:** each row names the check that reproduces the symptom; add a row only when you have verified both sides.

| Symptom | Check |
|---------|-------|
| No bar at all | `pgrep waybar`; if empty, run `waybar -c waybar/config.jsonc -s waybar/style.css` and inspect stderr |
| CSS parse error on launch | Generated `waybar/colors.css` missing; run `scripts/toggle_theme.sh init` |
| Theme indicator stuck | Check `.theme_state` and `gsettings get org.gnome.desktop.interface color-scheme` |
| Battery missing | `upower -e` must list `/org/freedesktop/UPower/devices/DisplayDevice` |
| Missing glyphs | Install a Nerd Font (the config asks for `SauceCodePro Nerd Font`) |
| Bluetooth icon stuck off | `bluez` running? `rfkill list bluetooth` shows the controller? |
| Clamshell suspends unexpectedly | `$XDG_RUNTIME_DIR/sway/monitor-hotplug.log` + verify `HandleLidSwitch=ignore` in `/etc/systemd/logind.conf.d/` |
| Monitor profile not applied | `$XDG_RUNTIME_DIR/sway/monitor-hotplug.log` logs the detected identity and which source set each value |
| Wallpaper doesn't change | Rotation is on-demand; press `$mod+Shift+w`. Pool folder exists with ≥1 `.png/.jpg/.jpeg`? Run `scripts/rotate-wallpaper.sh` and check `readlink images/wp.png` |
| Screenshare finds no source | `xdg-desktop-portal-wlr` installed? See [xdg-defaults.md](xdg-defaults.md#portals) |
| "Open in Terminal" opens the wrong app | See [xdg-defaults.md](xdg-defaults.md#default-terminal) |
| Files open in LibreOffice / wrong app | `gio mime <type>`; fix with `xdg-mime default` or re-run `scripts/setup-defaults.sh` |
