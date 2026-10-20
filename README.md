# cluster-health

Kubernetes cluster health in your desktop panel, for KDE Plasma 6 and GNOME Shell 45+, with desktop and Telegram alerts.

- **Down detection**: API reachability (`/readyz`) and the Alertmanager **Watchdog** alert. If Watchdog stops firing, your alerting pipeline is dead.
- **Pod health %**: healthy pods (Running and ready, or Succeeded) over total.
- **Tabs**: Pods, Alerts (firing Alertmanager alerts) and Warnings (recent `Warning` events), all filterable by namespace.
- **Recent pods**: newest first, with a colored state dot.
- **Multiple clusters**: one tab or section per kubeconfig.
- **Notifications**: `notify-send` and Telegram, sent once when a problem fires and once when it resolves.

## How it works

```
systemd user timer (60s)
  └─ cluster-health  ──kubectl──>  each cluster
        ├─ ~/.cache/cluster-health/status.json  ──>  KDE widget / GNOME extension (read only)
        └─ on change: notify-send + Telegram
```

The checker runs on any desktop. The panel UIs only read `status.json`.

## Requirements

`kubectl`, `jq`, `curl`, `notify-send` (libnotify), systemd. Your kubeconfigs must already work with `kubectl`.

Watchdog needs an Alertmanager service named `alertmanager` on port 9093 in the `monitoring` namespace (the kube-prometheus default). Clusters without one show Watchdog as `n/a`.

## Install

```bash
git clone https://github.com/anas1412/cluster-health.git
cd cluster-health
./install.sh
```

The installer:

1. copies `bin/cluster-health` to `~/.local/bin`
2. installs and starts the `cluster-health.timer` systemd user timer
3. installs the KDE widget if `plasmashell` is present, and the GNOME extension if `gnome-shell` is present
4. creates `~/.config/cluster-health/telegram.env` (empty)

Then add it to your panel:

- **KDE**: right-click the panel > Add or Manage Widgets > search **Cluster Health** > drag it onto the panel.
- **GNOME**: log out and back in (Wayland), then run `gnome-extensions enable cluster-health@anas.dev`.

Run `./install.sh` again to update.

## Pod states

| dot | state |
| --- | --- |
| 🟢 | Running and ready |
| 🟠 | Pending, or Running but not ready |
| 🔴 | Failed, CrashLoopBackOff, ImagePull errors, OOMKilled |
| ⚪ | Completed |

## Configure

Use the settings button in the widget (KDE gear icon, GNOME **Settings…** menu item or the Extensions app). Both write the same files in `~/.config/cluster-health/`, which you can also edit by hand.

### Clusters

`clusters` lists one kubeconfig path per line. The file name becomes the tab name. The default is `$KUBECONFIG` or `~/.kube/config`.

```
~/.kube/prod.yml
~/.kube/staging.yml
```

### Telegram

1. Create a bot with [@BotFather](https://t.me/BotFather) and copy its token.
2. Send your bot any message.
3. Open `https://api.telegram.org/bot<TOKEN>/getUpdates` and copy `message.chat.id`.
4. Enter the token and chat id in settings (KDE has a **Save and send test message** button), or fill in `telegram.env`:

```
TG_TOKEN=123456:ABC...
TG_CHAT=123456789
```

## What triggers a notification

| event | notified |
| --- | --- |
| API unreachable (after one retry) | yes |
| Watchdog missing | yes |
| new `critical` alert | yes |
| `warning` / `info` alerts, Warning events | widget only |

## Commands

```bash
cluster-health                                   # run a check now
systemctl --user list-timers cluster-health.timer
journalctl --user -u cluster-health.service
```

## Uninstall

```bash
systemctl --user disable --now cluster-health.timer
rm ~/.local/bin/cluster-health ~/.config/systemd/user/cluster-health.*
kpackagetool6 -t Plasma/Applet -r dev.anas.clusterhealth           # KDE
rm -r ~/.local/share/gnome-shell/extensions/cluster-health@anas.dev  # GNOME
```

## License

MIT
