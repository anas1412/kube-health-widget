#!/usr/bin/env bash
# Install:    curl -fsSL https://raw.githubusercontent.com/anas1412/cluster-health/main/install.sh | bash
# Update:     ~/.local/share/cluster-health/install.sh --update   (run daily by cluster-health-update.timer)
# Uninstall:  ~/.local/share/cluster-health/install.sh --uninstall
set -e
REPO=${CLUSTER_HEALTH_REPO:-https://github.com/anas1412/cluster-health.git}
SRC=$HOME/.local/share/cluster-health
UNITS=$HOME/.config/systemd/user
GNOME_EXT=$HOME/.local/share/gnome-shell/extensions/cluster-health@anas.dev

case "${1:-}" in
  --uninstall)
    systemctl --user disable --now cluster-health.timer cluster-health-update.timer 2>/dev/null || true
    rm -f "$HOME/.local/bin/cluster-health" "$UNITS"/cluster-health.{service,timer} "$UNITS"/cluster-health-update.{service,timer}
    systemctl --user daemon-reload
    command -v kpackagetool6 >/dev/null && kpackagetool6 -t Plasma/Applet -r dev.anas.clusterhealth >/dev/null 2>&1 || true
    command -v gnome-extensions >/dev/null && gnome-extensions disable cluster-health@anas.dev 2>/dev/null || true
    rm -rf "$GNOME_EXT" "$SRC"
    echo "Uninstalled. Config kept in ~/.config/cluster-health"
    exit 0 ;;
  --update)
    git -C "$SRC" fetch -q origin
    [ "$(git -C "$SRC" rev-parse HEAD)" = "$(git -C "$SRC" rev-parse '@{u}')" ] && exit 0
    git -C "$SRC" reset -q --hard '@{u}'
    exec "$SRC/install.sh" --updated ;;
esac

missing=$(for c in git kubectl jq curl; do command -v "$c" >/dev/null || echo -n "$c "; done)
[ -z "$missing" ] || { echo "Missing: $missing"; exit 1; }

# Run from curl or from another folder: fetch the checkout, then continue with its installer.
here=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
if [ "$here" != "$SRC" ]; then
  if [ -d "$SRC/.git" ]; then git -C "$SRC" pull -q --ff-only; else git clone -q "$REPO" "$SRC"; fi
  exec "$SRC/install.sh" "$@"
fi
cd "$SRC"

install -Dm755 bin/cluster-health "$HOME/.local/bin/cluster-health"
install -Dm644 -t "$UNITS" systemd/*.service systemd/*.timer
systemctl --user daemon-reload
systemctl --user enable --now cluster-health.timer cluster-health-update.timer >/dev/null 2>&1

conf=$HOME/.config/cluster-health
mkdir -p "$conf"
[ -f "$conf/telegram.env" ] || { printf 'TG_TOKEN=\nTG_CHAT=\n' > "$conf/telegram.env"; chmod 600 "$conf/telegram.env"; }

if command -v plasmashell >/dev/null; then
  kpackagetool6 -t Plasma/Applet -u kde >/dev/null 2>&1 || kpackagetool6 -t Plasma/Applet -i kde >/dev/null
fi
if command -v gnome-shell >/dev/null; then
  mkdir -p "$GNOME_EXT" && cp gnome/cluster-health@anas.dev/* "$GNOME_EXT"/
  gnome-extensions enable cluster-health@anas.dev 2>/dev/null || true
fi

version=$(git log -1 --format='%h %s')
if [ "${1:-}" = "--updated" ]; then
  notify-send -a "Cluster Health" "Cluster Health updated" "$version
Widget changes load after you log out and back in." 2>/dev/null || true
  exit 0
fi

echo "Installed $version"
command -v plasmashell >/dev/null && echo "KDE: right-click the panel > Add or Manage Widgets > Cluster Health"
command -v gnome-shell >/dev/null && echo "GNOME: log out and back in if the icon is missing, then: gnome-extensions enable cluster-health@anas.dev"
echo "Settings: open the widget and click the gear icon. Auto-update: daily."
