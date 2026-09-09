# Utility scripts

These scripts live in `scripts/` and are invoked in place from `$HOME/.config/sway/scripts/`. Keybinds and `exec` lines reference them by that path, so there's nothing to copy elsewhere.

- `move-ws-to-active.sh`: Moves all workspaces to the currently focused output. Not bound by default; available for a keybind or manual use.
- `move-ws-to-output.sh`: Moves all workspaces to a specific output (arg 1). Not bound by default; available for a keybind or manual use.
- `toggle-touchpad.sh`: Toggles the touchpad on/off and sends a notification.
- `hooks.sh`: Event hook dispatcher. Runs every executable in `hooks/<event>.d/` (tracked) and then `hooks.local/<event>.d/` (machine-local overlay, gitignored), in sorted order, passing the event name as `$1`. Missing directories are a silent no-op; a failing hook is logged and skipped without stopping the rest. Wired for `post-boot` (end of `config`) and `theme-set` (end of every theme flip). See `docs/hooks.md`.
- `mako-mode-sync.sh`: Re-applies mako's `DoNDisturb` mode from the `dnd` toggle flag. Called by `toggle_theme.sh` after every `makoctl reload`, which restarts the daemon and silently drops active custom modes. Read-then-act (`makoctl mode` first, add only if absent, remove only if present), so it is idempotent. Silent no-op when `makoctl` or the flag store is absent.
- `screenshot.sh`: Captures with `grim`, writes the PNG to `~/Pictures/Screenshots`, and copies it to the clipboard so it can be pasted directly instead of attached from disk.
    - **Modes** (arg 1, default `region`): `region` (drag a selection with `slurp`), `screen` (whole output layout), `output` (focused output, via `grim -o` so its scale is preserved), `window` (focused window).
    - **Bound by default:** `Ctrl+Alt+s` → `region`, `Print` → `screen`. `output` and `window` are unbound; add a keybind if you want them.
    - **Degradation:** no `grim` or a cancelled `slurp` selection exits silently; without `wl-copy` the capture is still saved, just not copied; `window`/`output` need `jq` and fall through to no capture without it.
    - **Save location:** `SCREENSHOT_DIR` overrides the directory; it's created on first capture.
- `osd-bar.sh`: Writes a 0-100 value to the wob OSD pipe (`$XDG_RUNTIME_DIR/sway/wob.sock`, config in `extra/wob/wob.ini`). Called by the volume/brightness control scripts after every change; wob not running or a missing pipe is a silent no-op. The OSD is feedback, never an error surface.
- `quick-menu.sh`: Domain quick menus in wofi (dmenu mode): `<audio|network|bluetooth|power>`, reached from `$super+Ctrl+a/w/b/p`, the network and bluetooth pills' left-clicks, and the audio pill's dropdown (its devices item delegates here). Audio: default sink/source switching, mute entries (via `wpctl`). Network: NetworkManager scan/connected-state, saved profiles, masked password entry for new networks (wofi's `-P`), iwd fallback, TUI escape hatch. Bluetooth: power toggle, connect/disconnect for paired devices, TUI for pairing. Power: delegates to `extra/wofi/wofi-power.sh`. Every backend is probed first and the menu silently skips when absent; a dismissed menu is a no-op; every external call runs under `timeout` so a wedged daemon can't hang the popup.
- `toggle-bluetooth.sh`: Toggles the bluetooth radio (`bluetoothctl power on/off`) and notifies. Bound to the bluetooth bar module's right-click.
- `volume-control.sh`: Handles mute, volume up/down, and mic mute.
    - Prefers `wpctl` on PipeWire systems.
    - Falls back to `pactl` for PulseAudio-compatible sessions.
    - Intended for media-key bindings that should work across built-in and USB keyboards.
    - Pushes the new level to the wob OSD (`scripts/osd-bar.sh`); mic mute notifies instead (no numeric level worth a bar).
- `brightness-control.sh`: Handles brightness up/down for laptop backlights.
    - Uses `brightnessctl` when the backlight directory is available (`BACKLIGHT_DIR` overrides `/sys/class/backlight`, for tests).
    - Exits silently on desktops or systems without a controllable backlight.
    - Pushes the new level to the wob OSD (`scripts/osd-bar.sh`).
- `external-brightness.sh`: Brightness up/down for external monitors over DDC/CI (`ddcutil`). Bound to `$super+Shift+Up/Down`.
    - A `getvcp` round-trip is slow, so the current/max pair is cached in `$XDG_RUNTIME_DIR/sway-brightness-ext`, the same cache `waybar/modules/brightness.sh` reads. Only a cache miss falls back to `getvcp`.
    - Exits silently without `ddcutil`.
    - Pushes the new level to the wob OSD (`scripts/osd-bar.sh`).
- `network-tui.sh`: Launches the best available network management TUI in kitty for the Waybar network click handler.
    - **Probe order:** `impala` (recommended; requires `iwd` as the wifi backend) → `nmtui` (requires NetworkManager) → `iwctl` (iwd interactive shell).
    - **Fallback:** read-only `ip -c -br a` + `ip -c r` summary with `kitty --hold` so the window stays open.
    - **Adding a TUI:** install one of the above and the script picks it up automatically, no config edit needed.
- `bluetooth-tui.sh`: Launches the best available bluetooth management TUI in kitty for the Waybar bluetooth click handler.
    - **Probe order:** `bluetuith` (recommended; ncurses TUI) → `bluetoothctl` (interactive shell). Also the pairing path for the quick menu (pairing needs an agent and a user confirmation).
    - **Adding a TUI:** install `bluetuith` and the script picks it up automatically.
- `power-events.sh`: Battery/AC event watcher, started once per session by a guarded `exec` in `config` (next to the mako guard). Polls UPower's DisplayDevice every 30s and fires one notification plus one hook per transition: `battery-low` (≤20% on discharge, once per episode), `battery-charged`, `power-plugged`, `power-unplugged` (see `docs/hooks.md`). State lives in `$XDG_RUNTIME_DIR/sway/power-events.state` so each episode fires exactly once; a pid file keeps a stray second copy from double-notifying. Tunables for testing: `POWER_EVENTS_INTERVAL`, `POWER_EVENTS_LOW_PCT`.
    - **Degradation:** without `upower`, without a battery (desktops), or without a usable runtime dir it exits 0 at the first probe, silent forever after.
    - **Notifications:** ordinary urgency, so mako's DoNDisturb mode suppresses them like every other notification.
- `idle-manager.sh`: Starts swayidle with the session's idle handling: lock after 10 minutes idle, display off after 15 (resume powers it back on), and always lock before suspend (`-w` so the lock finishes first). Timings are user-configurable in `host.env` (`LOCK_TIMEOUT` / `SCREEN_OFF_TIMEOUT`, seconds; `0` disables a timeout; copy `host.env.example`). Edit, then run the script again: it restarts the previous instance via a pid file, no reload needed. While the `stay-awake` flag is set (see `toggle-stay-awake.sh`) the lock and screen-off commands no-op; the before-sleep lock always runs.
    - **Started by** a guarded `exec` in `config.d/idle` once per session. swaylock intentionally has no `timeout` wrapper; it must block until the session is unlocked.
- `toggle-stay-awake.sh`: Toggles stay-awake mode (`stay-awake` flag in the flag store) and notifies. While set, idle-manager's lock and screen-off timeouts no-op, so a presentation or reading session stays on and unlocked; locking before a manual suspend still happens. Bound to `$super+Ctrl+s` and the bar indicator's click; never survives a session (runtime-dir flag).
- `monitor-hotplug.sh`: Auto-switches between "Mobile" (internal screen only) and "Docked" (external screen only) modes.
    - **Logic:**
        - If an external monitor is connected:
            - Enables the external monitor.
            - Moves all workspaces to it.
            - Disables the internal display by default (configurable via `DISABLE_INTERNAL_ON_EXTERNAL="true"` in the script).
            - If `DISABLE_INTERNAL_ON_EXTERNAL` is set to "false" and the lid is open, enables the internal display in extended mode.
        - If no external monitor is connected:
            - Enables the internal display.
            - Moves all workspaces to it.
            - If the laptop lid is closed, **suspends** the system (ensures it doesn't stay awake in your bag).
    - **Hardware Support:** Internal display is auto-detected as the first `eDP-*` output. Lid state is read from the first available `/proc/acpi/button/lid/*/state` entry when present.
    - **Logging:** Logs actions to `$XDG_RUNTIME_DIR/sway/monitor-hotplug.log`.
    - **External output settings precedence:**
        1. `DOTSWAY_EXT_*` environment variables (session env)
        2. `host.env` at the repo root (copy `host.env.example`), the same `DOTSWAY_EXT_*` names
        3. Per-monitor matches from `~/.config/sway/scripts/monitor-profiles.local.sh`
        4. Universal fallback defaults (`1920x1080@60Hz`, scale `1`, adaptive sync `off`)
    - **Per-monitor setup:**
        - Copy `scripts/monitor-profiles.example.sh` to `~/.config/sway/scripts/monitor-profiles.local.sh`.
        - Use `swaymsg -t get_outputs -r` to capture the external display `name`, `make`, `model`, and `serial`.
        - Add a `dotsway_monitor_profile()` case entry that calls `set_monitor_profile MODE SCALE ADAPTIVE_SYNC`.
        - Reload Sway and run `~/.config/sway/scripts/monitor-hotplug.sh --once` to re-apply immediately.
        - Check `$XDG_RUNTIME_DIR/sway/monitor-hotplug.log` if the detected values or applied settings do not look right.
    - **Environment variables** (set in the session environment or in `host.env`, where a non-empty env var wins, to force the same external monitor behaviour everywhere):

        | Variable | Default | Description |
        |---|---|---|
        | `DOTSWAY_EXT_RES` | `1920x1080@60Hz` | Forced mode string for the external monitor (e.g. `3840x2160@120Hz`) |
        | `DOTSWAY_EXT_SCALE` | `1` | Forced output scale factor (e.g. `1.25` for a 4K display) |
        | `DOTSWAY_EXT_ADAPTIVE_SYNC` | `off` | Enable adaptive sync (`on`/`off`) |
        | `DOTSWAY_INTERNAL_OUTPUT` | *(auto)* | Force a specific internal output name (e.g. `eDP-1`) |
        | `DOTSWAY_MONITOR_PROFILES_FILE` | `~/.config/sway/scripts/monitor-profiles.local.sh` | Alternate path for local per-monitor overrides |

- `rotate-wallpaper.sh`: Picks a random `.png/.jpg/.jpeg` from the wallpaper pool, repoints the `images/wp.png` symlink at it, and applies the change live via `swaymsg output * bg`. Bound to `$mod+Shift+w` for on-demand switching. `config.d/wallpaper` runs it with `--if-unset` on start/reload, which only picks when `wp.png` isn't already set, so reloads and logins keep the current wallpaper.
    - **Pool location:** `images/wallpapers/` by default. `WALLPAPER_DIR` in `host.env` (gitignored; copy `host.env.example`) redirects it to any external folder, e.g. a synced image library; only top-level files are scanned, so a subfolder of a larger collection works. A set-but-missing directory warns and falls back to the in-repo pool.
    - **Empty/absent pool:** an already-set `wp.png` is left alone; otherwise it falls back to the bundled wallpaper (`images/wallpapers/frederic-church-parthenon.jpg`), so `wp.png` always resolves (no black desktop, no broken swaylock image) even on a fresh checkout with an empty pool.
    - **Lock screen:** the swaylock keybind and the idle lock (`config.d/idle` via `scripts/idle-manager.sh`) consume `images/wp.png`, so the lock screen follows rotation automatically, no extra wiring.
    - **Override the repo dir:** set `SWAY_DIR=/some/other/path` before invoking; the script resolves `images/`, `host.env`, and the default pool underneath it.
- `install-release.sh`: Installs a non-repo tool from a pinned release into `/opt/<name>/` with `/usr/local/bin` symlinks, the pattern for tools the distro doesn't package well (nvim, teams-for-linux). Verifies the SHA256 from the release notes before touching system dirs; a mismatch aborts before anything is written.
    - **Usage:** `install-release.sh <name> <url> <sha256>`. The payload is detected by content: tarballs extract into `/opt/<name>/` and executables from a `bin/` dir (or the tarball root) get symlinked; a plain file is symlinked into `/usr/local/bin` as `<name>`.
    - **Never overwrites:** if `/opt/<name>` already exists, it refuses and tells you to remove it first.
    - **Needs sudo** for the install steps (one prompt). Not bound; run manually.
- `check-core-features.sh`: Probes the local machine against the matrix in `docs/core-features.md` and prints a ✓/!/✗ table (binaries, packages, units, agent socket). Read-only; safe to run anywhere, no root needed.
    - **Exit code:** 0 when nothing is missing, 1 when any feature is ✗ (a degraded/N-A `!` does not fail).
    - **Not bound**; run manually after provisioning or hardware changes, or before claiming a distro column in the matrix is verified.
- `toggle.sh`: Per-session toggle flag store: plain files under `${XDG_RUNTIME_DIR:-/tmp}/sway/toggles/` (0700, wiped on logout), so toggled state resets to the fresh-session default on every start. Subcommands: `toggle.sh set <name> [value]`, `toggle.sh unset <name>`, `toggle.sh get <name>` (exit 0/1, prints nothing). Names are restricted to `[A-Za-z0-9_-]`. It's a dumb store: the owning toggle script writes its own flag; the Waybar indicators (`waybar/modules/theme.sh`, `waybar/modules/dnd.sh`) read it. Not bound; called by `toggle_theme.sh` and `toggle-mako-dnd.sh`.
- `toggle-mako-dnd.sh`: Toggles mako's `DoNDisturb` mode (`makoctl mode -a/-r`) and sets/unsets the `dnd` flag for the Waybar indicator. Bound to `$mod+Shift+m`; the `custom/dnd` module's `on-click` calls it. No-op when `makoctl` is absent.
- `toggle_theme.sh`: Switches the desktop between dark and light themes in one keypress (`Mod+Shift+t`). Source of truth is Gnome's `org.gnome.desktop.interface color-scheme` when `gsettings` is available, otherwise `~/.config/sway/.theme_state`. Writes the `theme` flag (with the resolved value) on every flip and at `init`, so the Waybar indicator matches on machines without gsettings.
    - **Updates in lockstep:**
        - Sway colors via `$XDG_RUNTIME_DIR/sway/sway_theme_config` (sourced from `config`)
        - Waybar palette by copying `colors-{dark,light}.css` into the generated `waybar/colors.css`. `reload_style_on_change` reloads CSS only. Neither `toggle` nor `init` sends `SIGUSR2`, which leaks monitor handlers on Waybar 0.12 and causes duplicate bars after hotplug.
        - Kitty theme (Tokyo Night Moon/Day) via `kitty @ set-colors`
        - Wofi theme by symlinking `~/.config/wofi/style.css`
        - Mako notification theme (when installed) with `makoctl reload`
        - Gnome `gtk-theme` (when available)
    - **Status indicator:** `waybar/modules/theme.sh` emits 🌙 (dark) or ☀️ (light) in the center cluster; click toggles. Resolution: gnome gsettings → `theme` flag → `.theme_state` → dark, so hybrid sessions keep gnome as the live source of truth.
    - **Subcommands:**
        - `toggle_theme.sh toggle`: flip
        - `toggle_theme.sh init`: re-apply current theme to all components (invoked at Sway startup)
        - `toggle_theme.sh get`: print `dark` or `light`
    - **Component prerequisites:**
        - **Waybar:** `waybar/colors-dark.css` and `waybar/colors-light.css` define the palette via `@define-color`. `colors.css` is a generated, gitignored regular file. Old symlinks are removed before copying so source palettes are never overwritten. The launcher runs from `waybar/` so Waybar 0.12 can find the imported file to watch. Missing source palettes are a silent no-op.
        - **Wofi:** no setup needed. `~/.config/wofi/style.css` is symlinked straight at the repo source `extra/wofi/style-{dark,light}.css`. See `extra/EXTRA.md`.
