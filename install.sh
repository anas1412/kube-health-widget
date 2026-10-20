#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
install -Dm755 bin/cluster-health ~/.local/bin/cluster-health
install -Dm644 -t ~/.config/systemd/user systemd/cluster-health.service systemd/cluster-health.timer
systemctl --user daemon-reload
systemctl --user enable --now cluster-health.timer

conf=~/.config/cluster-health
mkdir -p "$conf"
[ -f "$conf/telegram.env" ] || { printf 'TG_TOKEN=\nTG_CHAT=\n' > "$conf/telegram.env"; chmod 600 "$conf/telegram.env"; }

if command -v plasmashell >/dev/null; then
  kpackagetool6 -t Plasma/Applet -u kde 2>/dev/null || kpackagetool6 -t Plasma/Applet -i kde
  echo "KDE: right-click panel > Add Widgets > Cluster Health"
fi
if command -v gnome-shell >/dev/null; then
  d=~/.local/share/gnome-shell/extensions/cluster-health@anas.dev
  mkdir -p "$d" && cp gnome/cluster-health@anas.dev/* "$d"/
  gnome-extensions enable cluster-health@anas.dev 2>/dev/null || echo "GNOME: log out/in, then: gnome-extensions enable cluster-health@anas.dev"
fi
echo "Clusters: $conf/clusters   Telegram: $conf/telegram.env"
