#!/usr/bin/env bash
# Real Waybar regression: six theme flips, then a new headless output.
# Requires sway, waybar, dbus-run-session and jq. No live desktop is touched.
# Usage: bash tests/waybar-hotplug-sandbox.sh /path/to/repo
set -euo pipefail

REPO=$(realpath "${1:?usage: waybar-hotplug-sandbox.sh /path/to/repo}")
for tool in sway swaymsg waybar dbus-run-session jq; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done
SB="${3:-}"
if [[ -z "$SB" ]]; then SB=$(mktemp -d); fi
sway_pid="" bar_pid=""
cleanup() {
  [[ -z "$bar_pid" ]] || kill "$bar_pid" 2>/dev/null || true
  [[ -z "$sway_pid" ]] || kill "$sway_pid" 2>/dev/null || true
  wait 2>/dev/null || true
  rm -rf "$SB"
}
trap cleanup EXIT
export HOME="$SB/home" XDG_RUNTIME_DIR="$SB/runtime"
export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share" XDG_STATE_HOME="$HOME/.local/state"
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
export GIO_USE_VFS=local NO_AT_BRIDGE=1
unset SWAYSOCK WAYLAND_DISPLAY DISPLAY
mkdir -p "$HOME/.config/sway" "$XDG_RUNTIME_DIR" "$SB/bin"
chmod 700 "$XDG_RUNTIME_DIR"
# No service directories: the test needs a bus, not desktop portal services
# or FUSE mounts that could outlive it. No host session sockets are inherited.
if [[ "${2:-}" != --session ]]; then
  cat > "$SB/dbus.conf" <<'BUS'
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
    <allow own="*"/>
  </policy>
</busconfig>
BUS
  dbus-run-session --config-file "$SB/dbus.conf" -- bash "$0" "$REPO" --session "$SB"
  exit
fi
cp -a "$REPO/scripts" "$REPO/waybar" "$HOME/.config/sway/"
# Never follow a copied runtime palette link out of the sandbox.
rm -f "$HOME/.config/sway/waybar/colors.css"
for tool in gsettings kitty notify-send mako makoctl pgrep; do
  printf '#!/bin/sh\nexit 1\n' > "$SB/bin/$tool"
  chmod +x "$SB/bin/$tool"
done
# Old theme code must exercise the actual reload bug, but only in our process.
cat > "$SB/bin/pkill" <<'STUB'
#!/bin/sh
if [ "$*" = '-SIGUSR2 -x waybar' ]; then
  kill -USR2 "$TEST_WAYBAR_PID"
fi
STUB
chmod +x "$SB/bin/pkill"
export PATH="$SB/bin:$PATH"

printf 'output * mode 1280x720\n' > "$SB/sway.conf"
sway -c "$SB/sway.conf" > "$SB/sway.log" 2>&1 &
sway_pid=$!
for ((i=0; i<100; i++)); do
  sockets=("$XDG_RUNTIME_DIR"/sway-ipc.*.sock)
  displays=("$XDG_RUNTIME_DIR"/wayland-*)
  if [[ -S "${sockets[0]}" && -S "${displays[0]}" ]]; then
    export SWAYSOCK="${sockets[0]}" WAYLAND_DISPLAY="${displays[0]##*/}"
    break
  fi
  sleep 0.1
done
if [[ -z "${SWAYSOCK:-}" ]]; then
  cat "$SB/sway.log" >&2
  exit 1
fi

bash "$HOME/.config/sway/scripts/toggle_theme.sh" init
# Keep the repository's reload setting and CSS, without hardware modules.
jq -n --arg config "$HOME/.config/sway/waybar/config.jsonc" \
  '{include: [$config], "modules-left": [], "modules-center": [], "modules-right": ["clock"]}' \
  > "$SB/waybar.json"
cd "$HOME/.config/sway/waybar"
waybar -l debug -c "$SB/waybar.json" -s "$PWD/style.css" > "$SB/waybar.log" 2>&1 &
bar_pid=$!
export TEST_WAYBAR_PID="$bar_pid"
wait_for_log() {
  for ((i=0; i<100; i++)); do
    if grep -q "$1" "$SB/waybar.log"; then return 0; fi
    kill -0 "$bar_pid" 2>/dev/null || break
    sleep 0.1
  done
  cat "$SB/waybar.log" >&2
  return 1
}
wait_for_log 'Bar configured.*HEADLESS-1'
for ((flip=0; flip<6; flip++)); do
  bash "$HOME/.config/sway/scripts/toggle_theme.sh" toggle
  # Allow both the old full reload and the CSS file monitor to settle.
  sleep 1
done
swaymsg create_output >/dev/null
wait_for_log 'Bar configured.*HEADLESS-2'
sleep 1
count=$(grep -c 'Bar configured.*HEADLESS-2' "$SB/waybar.log")
printf 'After six theme flips and hotplug: %s bars on HEADLESS-2, expected 1\n' "$count"
if [[ "$count" != 1 ]]; then
  cat "$SB/waybar.log" >&2
  exit 1
fi
if grep -q 'Reloading\.\.\.' "$SB/waybar.log"; then
  echo 'FAIL: theme flip performed a full Waybar reload' >&2
  exit 1
fi
reloads=$(grep -c 'Reloading style, file changed: .*colors.css' "$SB/waybar.log" || true)
printf 'CSS-only palette reloads: %s, expected 6\n' "$reloads"
[[ "$reloads" == 6 ]]
! grep -q '\[error\]' "$SB/waybar.log"
