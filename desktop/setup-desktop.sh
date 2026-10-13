#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTOSTART_FILE="$HOME/.config/autostart/aegisos.desktop"
DESKTOP_FILE="$HOME/Desktop/UniTrack.desktop"
LEGACY_DESKTOP_FILE="$HOME/Desktop/Uni Track.desktop"
WALLPAPER="$HOME/.local/share/backgrounds/unitrack-wallpaper.png"

if ! command -v xfconf-query >/dev/null 2>&1; then
    sudo apt update
    sudo apt install -y xfce4 xfce4-goodies
fi

# Xfce does not reliably render images linked from SVG wallpapers.
install -Dm644 "$SCRIPT_DIR/assets/unitrack-wallpaper.png" "$WALLPAPER"
install -Dm644 "$SCRIPT_DIR/assets/unitrack-mark.png" "$HOME/.local/share/icons/unitrack-mark.png"

render_launcher() {
    local destination="$1"
    mkdir -p "$(dirname "$destination")"
    sed "s|__START_SCRIPT__|$PROJECT_ROOT/desktop/start-aegis.sh|g; s|__ICON__|$HOME/.local/share/icons/unitrack-mark.png|g" \
        "$SCRIPT_DIR/templates/aegisos.desktop.in" >"$destination"
    chmod +x "$destination"
}

render_launcher "$AUTOSTART_FILE"
render_launcher "$DESKTOP_FILE"
if [[ -f "$LEGACY_DESKTOP_FILE" ]] && grep -Fq "Exec=$PROJECT_ROOT/desktop/start-aegis.sh" "$LEGACY_DESKTOP_FILE"; then
    rm -- "$LEGACY_DESKTOP_FILE"
fi
chmod +x "$PROJECT_ROOT/desktop/start-aegis.sh" "$PROJECT_ROOT/start-aegis.sh"

if command -v xfconf-query >/dev/null 2>&1 && [[ "${XDG_CURRENT_DESKTOP:-}" == *XFCE* ]]; then
    while IFS= read -r property; do
        case "$property" in
            */last-image|*/image-path)
                xfconf-query -c xfce4-desktop -p "$property" -s "$WALLPAPER" || true
                ;;
        esac
    done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null || true)
else
    echo "Log into an Xfce Session to apply the wallpaper automatically."
fi

echo "UniTrack desktop launcher installed at: $DESKTOP_FILE"
echo "UniTrack XFCE autostart installed at: $AUTOSTART_FILE"
echo "Log out and choose 'Xfce Session', or run desktop/start-aegis.sh now."
