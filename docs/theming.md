# Theme toggle & wallpaper

**What:** The unified dark/light theme across bar, terminal, launcher, and notifications, plus on-demand wallpaper rotation.
**Where:** `scripts/toggle_theme.sh` and `scripts/rotate-wallpaper.sh`; the palettes in `waybar/colors-{dark,light}.css`; per-app bits in `extra/{kitty,wofi,mako}`.
**Verified:** `tests/theme-sandbox.sh` in CI, running the real `toggle_theme.sh` and `scripts/mako-mode-sync.sh` in a throwaway `$HOME` with session binaries stubbed to check theme updates, palette migration, signal-free Waybar updates, mako mode restoration, and hook dispatch.

## Theme toggle (dark/light)

A single keybind (`Mod+Shift+t`) flips Sway, Waybar, kitty, wofi, mako, and (under GNOME) Gnome's `color-scheme` between dark and light. The script is `scripts/toggle_theme.sh`; it runs `init` at Sway startup to bootstrap all components.

- **Status indicator:** 🌙 dark / ☀️ light (`waybar/modules/theme.sh`).
- **Gnome sync:** when `gsettings` reports `org.gnome.desktop.interface color-scheme`, that is the source of truth; otherwise `.theme_state` is.
- Waybar watches the generated `colors.css` for CSS-only reloads. Theme changes copy the selected palette into that file without signalling or restarting Waybar. See [waybar.md](waybar.md) for the Waybar 0.12 hotplug bug this avoids.
- **Kitty:** Tokyo Night (MIT, bundled in `extra/kitty/themes/`). On a fresh box, `init` seeds `~/.config/kitty/` (theme files into the conventional `~/.config/kitty/themes/` + a minimal `kitty.conf`); existing kitty configs are never overwritten, and a `tokyo_night_*.conf` you install in that themes dir wins over the bundled copy. See `extra/EXTRA.md`.

```bash
scripts/toggle_theme.sh toggle   # flip
scripts/toggle_theme.sh init     # re-apply current theme to all components
scripts/toggle_theme.sh get      # print "dark" or "light"
```

## Wallpaper rotation

Rotation is **on-demand**. Press `$mod+Shift+w` to switch to a fresh random wallpaper; otherwise the current one persists across reloads and logins. `scripts/rotate-wallpaper.sh` does the work:

1. Scans the pool for `.png/.jpg/.jpeg` (case-insensitive, top level). Pool is `images/wallpapers/` by default; `WALLPAPER_DIR` in the gitignored `host.env` (copy `host.env.example`) can point it at an external folder.
2. Picks one uniformly at random.
3. Repoints the `images/wp.png` symlink at the pick.
4. Applies it live with `swaymsg output * bg images/wp.png fill`.

`config.d/wallpaper` runs the script with `--if-unset` on each start/reload. That is a **bootstrap only**: it sets a wallpaper when `wp.png` isn't already an existing file (e.g. a fresh checkout), either a random pool pick or the bundled wallpaper when the pool is empty, and is a no-op otherwise, so `$mod+Shift+c` (reload) and logins keep whatever you last chose.

Because everything that references the wallpaper reads `images/wp.png`, the lock screen follows your pick automatically: the active swaylock keybind (`$super+l`) uses it, and so does the idle lock that `config.d/idle` runs via `scripts/idle-manager.sh` (its `timeout`/`before-sleep` hooks).

```bash
cp ~/Pictures/*.jpg ~/.config/sway/images/wallpapers/   # add wallpapers
$mod+Shift+w                                            # switch to a random pick
scripts/rotate-wallpaper.sh                             # or roll directly
```

With an empty or missing pool, an already-set `wp.png` is left untouched; a fresh checkout falls back to the bundled wallpaper so the desktop is never blank and the swaylock image always loads.

**Cold-boot note:** Sway parses `output * bg` before `exec_always` fires, so the boot wallpaper is whatever `wp.png` pointed at when you last shut down. Since start-up no longer rotates, there's no flash; the persisted wallpaper is what you see. Only a first-run checkout (no `wp.png` yet) shows a blank background for a moment at parse, until the bootstrap points `wp.png` at the bundled wallpaper (or a pool pick) just after login.
