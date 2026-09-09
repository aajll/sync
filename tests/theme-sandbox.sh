#!/usr/bin/env bash
# theme-sandbox.sh: sandboxed assertion suite for scripts/toggle_theme.sh
#
# Runs the script against a throwaway $HOME with the repo copied in (never a
# symlink, so .theme_state and friends must not leak into the real tree), with
# every session-external binary stubbed and SWAYSOCK unset. The notify-send
# stub exits 1 on purpose: a Sway desktop without a notification daemon is a
# normal state, and the script must survive it with exit 0.
#
# Usage: theme-sandbox.sh /path/to/repo
# Exit:  0 when every assertion passes; prints N/M summary.
set -euo pipefail

REPO="${1:?usage: theme-sandbox.sh /path/to/repo}"
[[ -f "$REPO/scripts/toggle_theme.sh" ]] || { echo "not a repo root: $REPO" >&2; exit 2; }

pass=0 fail=0
assert() { # assert <desc> <cmd...>
  local desc="$1"
  shift
  if "$@"; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$desc"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n' "$desc"
  fi
}
eq() { [[ "${1-}" == "${2-}" ]]; }
has() { grep -q "$2" "$1" 2>/dev/null; }
link_to() { [[ "$(readlink "$1" 2>/dev/null)" == "$2" ]]; }
same_as() { cmp -s "$1" "$2" 2>/dev/null; }

SB=""
new_sandbox() { # sets HOME_ RUNTIME_ BIN_ GNOME_LOG_
  SB=$(mktemp -d)
  HOME_="$SB/home"
  RUNTIME_="$SB/runtime"
  BIN_="$SB/bin"
  GNOME_LOG_="$SB/gsettings.log"
  Sway="$HOME_/.config/sway"
  mkdir -p "$HOME_/.config" "$RUNTIME_" "$BIN_"
  cp -a "$REPO" "$HOME_/.config/sway"
  # gsettings is stubbed too: the host's real one would make GNOME the
  # source of truth and let the host's actual theme drive the run.
  for b in swaymsg pkill gsettings kitty notify-send mako makoctl pgrep; do
    printf '#!/bin/sh\nexit 1\n' > "$BIN_/$b"
    chmod +x "$BIN_/$b"
  done
  # Record signals so repeated theme flips cannot reintroduce Waybar's
  # SIGUSR2 monitor-handler leak (upstream Waybar #4705).
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/signals"\nexit 1\n' "$SB" > "$BIN_/pkill"
  # The repo's working tree carries an untracked .theme_state; drop it so
  # the sandbox really is a fresh box.
  rm -f "$Sway/.theme_state"
}
install_mako_stubs() { # stateful makoctl: modes live in a file, reload resets it
  # `reload` mimics the daemon restart that drops custom modes in production;
  # the sync helper under test must re-add DoNDisturb after that reset.
  cat > "$BIN_/makoctl" <<EOF
#!/bin/sh
STATE="$SB/mako_modes"
[ -f "\$STATE" ] || echo default > "\$STATE"
cmd="\${1-}"
if [ "\$cmd" = reload ]; then
  echo default > "\$STATE"
elif [ "\$cmd" = mode ]; then
  if [ "\${2-}" = -a ]; then
    grep -qx "\$3" "\$STATE" || echo "\$3" >> "\$STATE"
  elif [ "\${2-}" = -r ]; then
    if grep -q "\$3" "\$STATE"; then
      grep -v "\$3" "\$STATE" > "\$STATE.tmp" && mv "\$STATE.tmp" "\$STATE"
    fi
  else
    cat "\$STATE"
  fi
fi
exit 0
EOF
  chmod +x "$BIN_/makoctl"
  # pgrep lies that mako is running, so the reload (and sync) path executes.
  printf '#!/bin/sh\nexit 0\n' > "$BIN_/pgrep"
  chmod +x "$BIN_/pgrep"
}
run_helper() { # run_helper <script> [args...] → sets RC and OUT
  local script="$1"
  shift
  OUT=$(env -u SWAYSOCK HOME="$HOME_" XDG_RUNTIME_DIR="$RUNTIME_" PATH="$BIN_:$PATH" \
    bash "$HOME_/.config/sway/$script" "$@" 2>/dev/null) && RC=0 || RC=$?
}
install_gnome_stub() { # gsettings stub that pretends GNOME is in dark mode
  # POSIX sh only: the stub runs under /bin/sh, which is dash on the CI
  # runner. `[[` would parse as a command-not-found and the stub would
  # return empty, which the script reads as "light".
  cat > "$BIN_/gsettings" <<EOF
#!/bin/sh
echo "gsettings \$*" >> "$GNOME_LOG_"
if [ "\${1-}" = get ] && [ "\${3-}" = color-scheme ]; then
  echo "string 'prefer-dark'"
fi
exit 0
EOF
  chmod +x "$BIN_/gsettings"
}
run_tts() { # run_tts <args...> → sets RC and OUT (stdout)
  OUT=$(env -u SWAYSOCK HOME="$HOME_" XDG_RUNTIME_DIR="$RUNTIME_" PATH="$BIN_:$PATH" \
    bash "$HOME_/.config/sway/scripts/toggle_theme.sh" "$@" 2>/dev/null) && RC=0 || RC=$?
}
cleanup() { [[ -n "$SB" ]] && rm -rf "$SB"; }
trap cleanup EXIT

# ---------------------------------------------------------------- S1: init, fresh box
new_sandbox
# Exercise migration from the old palette symlink without overwriting it.
ln -sfn colors-dark.css "$Sway/waybar/colors.css"
cp "$Sway/waybar/colors-dark.css" "$SB/dark-original.css"
run_tts init
assert "init exits 0"                 eq "$RC" 0
assert "init does not create .theme_state" bash -c "[[ ! -f '$HOME_/.config/sway/.theme_state' ]]"
assert "init writes dark sway_theme_config" has "$RUNTIME_/sway/sway_theme_config" 'set $bg_color #323232'
assert "Waybar enables CSS-only reloads" has "$Sway/waybar/config.jsonc" '"reload_style_on_change": true'
assert "init copies waybar dark palette" same_as "$Sway/waybar/colors.css" "$Sway/waybar/colors-dark.css"
assert "init replaces old palette symlink" test ! -L "$Sway/waybar/colors.css"
assert "init links wofi dark style"     link_to "$HOME_/.config/wofi/style.css" "$Sway/extra/wofi/style-dark.css"
# Theme files stage into kitty's conventional dir, ~/.config/kitty/themes/.
assert "init seeds user kitty.conf"     same_as "$HOME_/.config/kitty/kitty.conf" "$Sway/extra/kitty/kitty.conf"
assert "init seeds kitty moon theme"    same_as "$HOME_/.config/kitty/themes/tokyo_night_moon.conf" "$Sway/extra/kitty/themes/tokyo_night_moon.conf"
assert "init sets current-theme=moon"   same_as "$HOME_/.config/kitty/current-theme.conf" "$HOME_/.config/kitty/themes/tokyo_night_moon.conf"
assert "init seeds managed mako config" same_as "$HOME_/.config/mako/config" "$Sway/extra/mako/config-dark"
assert "init seeds theme flag (dark)"    eq "$(cat "$RUNTIME_/sway/toggles/theme")" "dark"

# ------------------------------------------------- S2: toggle dark→light (notify-send fails)
run_tts toggle
assert "toggle exits 0 despite failing notify-send" eq "$RC" 0
assert "toggle flips state to light"  eq "$(cat "$HOME_/.config/sway/.theme_state")" "light"
assert "toggle writes light config"   has "$RUNTIME_/sway/sway_theme_config" 'set $bg_color #f0f0f0'
assert "toggle copies waybar light" same_as "$Sway/waybar/colors.css" "$Sway/waybar/colors-light.css"
assert "toggle leaves dark source untouched" same_as "$Sway/waybar/colors-dark.css" "$SB/dark-original.css"
assert "toggle links wofi light"      link_to "$HOME_/.config/wofi/style.css" "$Sway/extra/wofi/style-light.css"
assert "toggle sets current-theme=day" same_as "$HOME_/.config/kitty/current-theme.conf" "$HOME_/.config/kitty/themes/tokyo_night_day.conf"
assert "toggle refreshes theme flag (light)" eq "$(cat "$RUNTIME_/sway/toggles/theme")" "light"

# ---------------------------------------------------------- S3: round trip back to dark
run_tts toggle
assert "round trip returns to dark" eq "$(cat "$HOME_/.config/sway/.theme_state")" "dark"
assert "round trip sets current-theme=moon" same_as "$HOME_/.config/kitty/current-theme.conf" "$HOME_/.config/kitty/themes/tokyo_night_moon.conf"
assert "round trip refreshes theme flag (dark)" eq "$(cat "$RUNTIME_/sway/toggles/theme")" "dark"
assert "round trip restores Waybar palette" same_as "$Sway/waybar/colors.css" "$Sway/waybar/colors-dark.css"
assert "theme updates never signal Waybar" bash -c "! grep -q waybar '$SB/signals' 2>/dev/null"

# ----------------------------------------------------------------------- S4: get
run_tts get
assert "get prints current theme" eq "$OUT" "dark"

# ------------------------------------- S5: user-customised mako config is never clobbered
new_sandbox
mkdir -p "$HOME_/.config/mako"
echo "user-custom mako" > "$HOME_/.config/mako/config"
run_tts toggle
assert "user mako config untouched" eq "$(cat "$HOME_/.config/mako/config")" "user-custom mako"

# ------------------------------------------------ S6: managed mako config keeps tracking theme
new_sandbox
mkdir -p "$HOME_/.config/mako"
cp "$Sway/extra/mako/config-dark" "$HOME_/.config/mako/config"
run_tts toggle
assert "managed mako config follows to light" same_as "$HOME_/.config/mako/config" "$Sway/extra/mako/config-light"

# --------------------------------------------------- S7: user-authored kitty.conf is never touched
new_sandbox
mkdir -p "$HOME_/.config/kitty"
echo "custom kitty.conf" > "$HOME_/.config/kitty/kitty.conf"
run_tts toggle
assert "user kitty.conf untouched" eq "$(cat "$HOME_/.config/kitty/kitty.conf")" "custom kitty.conf"
assert "current-theme still updated for user kitty" same_as "$HOME_/.config/kitty/current-theme.conf" "$HOME_/.config/kitty/themes/tokyo_night_day.conf"

# ------------------------------------------------ S8: user-installed kitty theme wins over repo copy
new_sandbox
mkdir -p "$HOME_/.config/kitty/themes"
echo "user moon theme" > "$HOME_/.config/kitty/themes/tokyo_night_moon.conf"
run_tts init
assert "user kitty theme wins" eq "$(cat "$HOME_/.config/kitty/current-theme.conf")" "user moon theme"

# ------------------------------------- S9: bad usage
new_sandbox
run_tts bogus
assert "unknown arg exits non-zero" bash -c "[[ $RC -ne 0 ]]"

# ------------------- S11: mako DoNDisturb survives a theme-flip reload (makoctl restarts)
new_sandbox
install_mako_stubs
run_helper scripts/toggle.sh set dnd
run_tts toggle
assert "flag set: flip re-applies DoNDisturb after reload" has "$SB/mako_modes" "DoNDisturb"

new_sandbox
install_mako_stubs
run_tts toggle
assert "flag unset: flip leaves DoNDisturb off" bash -c "! grep -q 'DoNDisturb' '$SB/mako_modes' 2>/dev/null"

new_sandbox
rm -f "$Sway/scripts/toggle.sh"
run_helper scripts/mako-mode-sync.sh
assert "helper exits 0 without flag store" eq "$RC" 0

# ------------------------------------- S10: GNOME present → gsettings is source of truth
new_sandbox
install_gnome_stub
run_tts get
assert "get queried gnome color-scheme" bash -c "grep -q 'gsettings get org.gnome.desktop.interface color-scheme' \"$GNOME_LOG_\""
run_tts toggle
assert "toggle asks gnome for prefer-light" bash -c "grep -q 'set org.gnome.desktop.interface color-scheme prefer-light' \"$GNOME_LOG_\""
assert "toggle asks gnome for Adwaita"      bash -c "grep -q 'set org.gnome.desktop.interface gtk-theme Adwaita' \"$GNOME_LOG_\""
assert "state file tracks the gnome flip"   eq "$(cat "$HOME_/.config/sway/.theme_state")" "light"
assert "gnome flip refreshes theme flag (light)" eq "$(cat "$RUNTIME_/sway/toggles/theme")" "light"

# -------------------------------------- S12: event hook dispatcher (scripts/hooks.sh)
new_sandbox
run_helper scripts/hooks.sh some-event
assert "dispatcher no-ops on unknown event" eq "$RC" 0

mkdir -p "$Sway/hooks/test.d"
printf '#!/bin/sh\nprintf "%%s\\n" "$1" > "%s/hook_out"\n' "$HOME_" > "$Sway/hooks/test.d/one.sh"
chmod +x "$Sway/hooks/test.d/one.sh"
printf '#!/bin/sh\nexit 3\n' > "$Sway/hooks/test.d/fail.sh"
chmod +x "$Sway/hooks/test.d/fail.sh"
printf '#!/bin/sh\ntouch "%s/second_ran"\n' "$HOME_" > "$Sway/hooks/test.d/two.sh"
chmod +x "$Sway/hooks/test.d/two.sh"
printf '#!/bin/sh\ntouch "%s/sample_ran"\n' "$HOME_" > "$Sway/hooks/test.d/three.sample"
run_helper scripts/hooks.sh test
assert "tracked hook ran with event name" eq "$(cat "$HOME_/hook_out" 2>/dev/null)" "test"
assert "failing hook did not stop the rest" bash -c "[[ -f '$HOME_/second_ran' ]]"
assert "non-executable sample does not run" bash -c "[[ ! -f '$HOME_/sample_ran' ]]"

mkdir -p "$Sway/hooks/order.d" "$Sway/hooks.local/order.d"
printf '#!/bin/sh\necho t >> "%s/order"\n' "$HOME_" > "$Sway/hooks/order.d/tracked.sh"
chmod +x "$Sway/hooks/order.d/tracked.sh"
printf '#!/bin/sh\necho l >> "%s/order"\n' "$HOME_" > "$Sway/hooks.local/order.d/overlay.sh"
chmod +x "$Sway/hooks.local/order.d/overlay.sh"
run_helper scripts/hooks.sh order
assert "hooks.local overlay runs after tracked" eq "$(tr -d '\n' < "$HOME_/order" 2>/dev/null)" "tl"

echo
echo "$pass/$((pass + fail)) assertions passed"
[[ "$fail" -eq 0 ]]
