#!/usr/bin/env bash
# Install:    curl -fsSL https://raw.githubusercontent.com/anas1412/kube-health-widget/main/install.sh | bash
# Update:     ~/.local/share/kube-health/install.sh --update   (run daily by kube-health-update.timer)
# Uninstall:  ~/.local/share/kube-health/install.sh --uninstall
set -e
REPO=${KUBE_HEALTH_REPO:-https://github.com/anas1412/kube-health-widget.git}
SRC=$HOME/.local/share/kube-health
UNITS=$HOME/.config/systemd/user
KDE_ID=io.github.anas1412.kubehealth
GNOME_UUID=kube-health@anas1412.github.io
GNOME_EXT=$HOME/.local/share/gnome-shell/extensions/$GNOME_UUID
ICON=$HOME/.local/share/icons/hicolor/scalable/apps/kube-health.svg
QDBUS=$(command -v qdbus6 || command -v qdbus || true)

# Swap every panel instance of widget $1 for widget $2 (no-op if Plasma is not running).
replace_kde_widget() {
  [ -n "$QDBUS" ] || return 0
  "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
    "panels().forEach(p => p.widgets('$1').forEach(w => { p.addWidget('$2'); w.remove() }))" >/dev/null 2>&1 || true
}

# Versions before 1.2 were called cluster-health; move settings over and remove the old pieces.
migrate_from_cluster_health() {
  local old_kde=dev.anas.clusterhealth old_gnome=cluster-health@anas.dev
  [ -e "$HOME/.local/bin/cluster-health" ] || [ -d "$HOME/.config/cluster-health" ] || return 0
  systemctl --user disable --now cluster-health.timer cluster-health-update.timer >/dev/null 2>&1 || true
  rm -f "$HOME/.local/bin/cluster-health" "$UNITS"/cluster-health.{service,timer} "$UNITS"/cluster-health-update.{service,timer} \
    "$HOME/.local/share/icons/hicolor/scalable/apps/cluster-health.svg"
  [ -d "$HOME/.config/cluster-health" ] && [ ! -d "$HOME/.config/kube-health" ] && mv "$HOME/.config/cluster-health" "$HOME/.config/kube-health"
  [ -d "$HOME/.cache/cluster-health" ] && [ ! -d "$HOME/.cache/kube-health" ] && mv "$HOME/.cache/cluster-health" "$HOME/.cache/kube-health"
  if command -v kpackagetool6 >/dev/null && kpackagetool6 -t Plasma/Applet -s "$old_kde" >/dev/null 2>&1; then
    replace_kde_widget "$old_kde" "$KDE_ID"
    kpackagetool6 -t Plasma/Applet -r "$old_kde" >/dev/null 2>&1 || true
  fi
  command -v gnome-extensions >/dev/null && gnome-extensions disable "$old_gnome" 2>/dev/null || true
  rm -rf "$HOME/.local/share/gnome-shell/extensions/$old_gnome" "$HOME/.local/share/cluster-health"
  echo "Migrated from cluster-health: settings moved to ~/.config/kube-health"
}

case "${1:-}" in
  --uninstall)
    systemctl --user disable --now kube-health.timer kube-health-update.timer 2>/dev/null || true
    rm -f "$HOME/.local/bin/kube-health" "$UNITS"/kube-health.{service,timer} "$UNITS"/kube-health-update.{service,timer} "$ICON"
    systemctl --user daemon-reload
    command -v kpackagetool6 >/dev/null && kpackagetool6 -t Plasma/Applet -r "$KDE_ID" >/dev/null 2>&1 || true
    command -v gnome-extensions >/dev/null && gnome-extensions disable "$GNOME_UUID" 2>/dev/null || true
    rm -rf "$GNOME_EXT" "$SRC"
    echo "Uninstalled. Settings kept in ~/.config/kube-health"
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

install -Dm755 bin/kube-health "$HOME/.local/bin/kube-health"
install -Dm644 icons/kube-health.svg "$ICON"
install -Dm644 -t "$UNITS" systemd/*.service systemd/*.timer

if command -v plasmashell >/dev/null; then
  kpackagetool6 -t Plasma/Applet -u kde >/dev/null 2>&1 || kpackagetool6 -t Plasma/Applet -i kde >/dev/null
fi
if command -v gnome-shell >/dev/null; then
  mkdir -p "$GNOME_EXT" && cp "gnome/$GNOME_UUID"/* icons/kube-health.svg "$GNOME_EXT"/
fi

# Runs after the new widget is installed, so panel instances can be swapped onto it.
migrate_from_cluster_health

systemctl --user daemon-reload
systemctl --user enable --now kube-health.timer kube-health-update.timer >/dev/null 2>&1
command -v gnome-shell >/dev/null && { gnome-extensions enable "$GNOME_UUID" 2>/dev/null || true; }

version=$(git log -1 --format='%h %s')
if [ "${1:-}" = "--updated" ]; then
  notify-send -a "Kube Health" "Kube Health updated" "$version
Widget changes load after you log out and back in." 2>/dev/null || true
  exit 0
fi

echo "Installed $version"
command -v plasmashell >/dev/null && echo "KDE: right-click the panel > Add or Manage Widgets > Kube Health"
command -v gnome-shell >/dev/null && echo "GNOME: log out and back in if the icon is missing, then: gnome-extensions enable $GNOME_UUID"
echo "Settings: open the widget and click the gear icon. Auto-update: daily."
