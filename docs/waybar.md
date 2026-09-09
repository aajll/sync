# Waybar (status bar)

**What:** The status bar (workspace and mode indicators, brightness, audio, theme, DND, stay-awake, swayi, bluetooth, network, tray, battery, clock) plus the contract custom shell modules must follow.
**Where:** `waybar/`: `config.jsonc` (layout), `style.css` + `colors-{dark,light}.css` (palette), `modules/` (custom shell modules), `menus/` (dropdown menu XML). Launched from `config.d/waybar`.
**Verified:** parse errors print to stderr when run in the foreground; the theme and DND custom modules are exercised by the CI theme suite (`tests/theme-sandbox.sh`).

Waybar is launched by `config.d/waybar` on Sway start. The snippet copies the active palette into the generated `waybar/colors.css`, then supervises Waybar, with up to five attempts after abnormal exits. It uses `exec`, not `exec_always`, so Sway reloads leave the bar running. Theme changes use `reload_style_on_change` to reload CSS without rebuilding the bar.

The launcher changes into the `waybar/` directory before starting Waybar. Version 0.12 resolves watched CSS imports relative to the working directory. `colors.css` must be a regular file, because its file watcher follows symlinks and would keep watching the old palette after a link swap.

Avoid `SIGUSR2` on Waybar 0.12. Each reload adds another monitor-event handler, so a later monitor connection creates duplicate bars. See [upstream fix #4705](https://github.com/Alexays/Waybar/pull/4705). The optional integration test `bash tests/waybar-hotplug-sandbox.sh "$PWD"` runs real Waybar in an isolated headless Sway session. Six theme flips followed by a new output must produce one bar and six CSS-only reloads. It requires Sway, Waybar, `dbus-run-session` and `jq`.

## Layout

| Cluster | Modules |
|---------|---------|
| Left    | `sway/workspaces`, `sway/mode` |
| Center  | `custom/brightness`, `pulseaudio`, `mpris`, `custom/theme`, `custom/dnd`, `custom/stay-awake`, `custom/swayi`, `bluetooth`, `network`, `custom/power` |
| Right   | `tray`, `battery`, `clock` |

Battery, audio, bluetooth, network, clock, and media (MPRIS now-playing with click-to-transport; hides itself when no player is active) use Waybar's native event-driven modules (D-Bus, no polling). Brightness, theme, DND, and stay-awake are custom shell modules under `waybar/modules/`. `custom/swayi` is the AI-usage pill. `waybar/modules/swayi.sh` in this tree is a delegator: it resolves `SWAYI_DIR` (env var > `host.env`) and execs the swayi checkout's module when one is present, printing nothing otherwise so the pill hides on machines without swayi.

## Pill framework

All pills share one set of CSS rules instead of per-module styling, so new modules get consistent spacing and hover for free:

- Waybar gives every label module's label (and the workspaces and tray boxes) the shared **`module`** CSS class, and sets the `:hover` state on mouse enter. A single `.module` rule in `style.css` therefore gives every pill uniform padding, rounded corners, and the `@bg_hover` highlight, the same affordance as the workspace buttons.
- `config.jsonc` sets `"spacing": 0` on purpose: each pill owns its 8px of padding per side, so gaps are a uniform 16px inside clusters and across cluster borders alike. Don't reintroduce per-module padding lists or `border-right` dividers; if a module must deviate, add an id-scoped override.
- `box#battery { padding: 0 }` is that kind of override: the battery module names *both* its box and its label `battery`, so without it the pill padding would apply twice.
- Workspaces keep per-button hover: `#workspaces:hover` suppresses the group-wide highlight so the highlight still telegraphs which workspace you're on.

## Toggle state

Theme (🌙/☀️) and DND (🧘) read per-session flag files written by the toggle scripts (`scripts/toggle.sh`; see [SCRIPTS.md](../scripts/SCRIPTS.md)). `theme.sh` resolves gnome gsettings → theme flag → `.theme_state`; `dnd.sh` shows the icon only while the `dnd` flag is set and mako is present; `stay-awake.sh` shows ☕ only while the `stay-awake` flag is set (idle lock and screen-off suspended).

## Dropdown menus

Four pills carry native Waybar dropdowns instead of wofi popups: **audio** (`pulseaudio`, left-click), **media** (`mpris`, left-click), **power** (the static `custom/power` pill ⚡, left-click), and **swayi** (Refresh; live session and weekly numbers stay on the hover tooltip because Waybar reads menu XML once at startup). All four menu XMLs live in `waybar/menus/`; swayi's is a copy of the checkout's file whose actions run through the delegator. Wired per module with three keys in `config.jsonc`:

- `"menu"`: the click that pops the menu (here always `on-click`).
- `"menu-file"`: GtkBuilder XML; must contain a `GtkMenu` with `id="menu"`, and each action is a `GtkMenuItem` with its own `id`. Use the explicit `<object class="...">` form; bare `<menu>` shorthand maps to `GtkMenuBar` in GtkBuilder.
- `"menu-actions"`: maps item `id`s to shell commands (run via `/bin/sh`, like `on-click`).

Two gotchas are baked into the config:

- The command and the menu fire on the *same* click, so a module with a menu must not also keep an `on-click` command (audio's old wofi call was dropped, not kept; its devices item delegates to the same script).
- `mpris` carries an empty `"on-click": ""`. It arms the menu handler and suppresses the module's built-in left-click play/pause. No such trick is needed for the other pills: the presence of the `"menu"` key itself enables the click handler on any `ALabel` module.

Styling: `menu` and `menuitem` selectors in `style.css` using palette tokens, so both themes apply. Dynamic lists stay in wofi (`scripts/quick-menu.sh`): native menus are static XML, so network's SSID scan and bluetooth's device list keep their left-click popups.

## Adding modules

- **Native module:** add its name to a `modules-*` array in `config.jsonc` and a config block below. See the [Waybar wiki](https://github.com/Alexays/Waybar/wiki). Native modules are preferred; they're event-driven. Every new module inherits the [pill framework](#pill-framework) padding and hover automatically, no per-module CSS needed.
- **Custom shell module:** drop an executable in `waybar/modules/`, then add `"custom/<name>"` to a cluster with `"exec"`, an `"interval"`, and an optional `"on-click"`. For state-dependent styling, emit JSON (`{text, tooltip, class, percentage}`) and set `"return-type": "json"` so `style.css` can then target `#custom-<name>.<class>`.

### The module output contract

Custom modules are polled on their interval, and the output rules are the interface:

- **One line per run.** Empty output hides the module: missing hardware or a missing tool prints nothing and exits 0, not an error.
- **Budget ~50ms per run.** If the source is slow (a DDC/CI probe, a daemon query), cache on the producer side and read the cache here. `brightness.sh` reads the cache that `scripts/external-brightness.sh` writes.
- **Probe before you call:** `command -v jq >/dev/null 2>&1 || exit 0`.

CSS edits reload automatically. Changes to `config.jsonc` or menu XML need a full Waybar restart on versions affected by #4705, not `SIGUSR2`. `swaymsg reload` does not relaunch Waybar. Stop the existing bar and relaunch with the command in `config.d/waybar`, or log out and back in.

## Theming

Edit `waybar/colors-dark.css` and `waybar/colors-light.css`; both **must define the same `@define-color` names** so `style.css` resolves in either palette. Don't put colors in `style.css`; use the semantic tokens (`@bg`, `@fg`, `@accent`, `@warning`, …). The theme toggle copies the selected palette into the generated `colors.css`, which Waybar watches for CSS-only reloads. After editing a source palette, run `scripts/toggle_theme.sh init` to apply the current theme. Do not edit `colors.css` directly; the next theme update overwrites it. See [theming.md](theming.md).
