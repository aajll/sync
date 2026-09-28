#!/usr/bin/env bash
# Generates a temporary config snippet for SwayFX features if it detects 'fx' in the version string.

set -euo pipefail

# Per-user runtime dir (0700, wiped on logout), not world-writable /tmp. The
# fallback keeps the script from hard-failing under `set -e` if the variable is
# unset (rare; only outside a normal systemd/elogind session).
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/sway"
mkdir -p "$RUNTIME_DIR"
CONFIG_SNIPPET="$RUNTIME_DIR/swayfx_config_snippet"

# Clear any previous snippet to ensure clean state (important for 'include' logic)
echo "" > "$CONFIG_SNIPPET"

# Check if SwayFX is running
if swaymsg -t get_version 2>/dev/null | grep -iq "fx"; then
    cat << EOF > "$CONFIG_SNIPPET"
# --- SwayFX Specific Settings (Generated) ---
# Enable blur effects (SwayFX)
blur enable
blur_xray enable

# Rounded corners (SwayFX)
corner_radius 10

# Dim inactive
default_dim_inactive 0.15
EOF
fi
