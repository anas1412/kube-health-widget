# cluster-health

Kubernetes cluster health in your desktop panel. Works on KDE Plasma 6 and GNOME Shell 45+, with desktop and Telegram alerts.

```bash
curl -fsSL https://raw.githubusercontent.com/anas1412/cluster-health/main/install.sh | bash
```

## Features

- **Down detection**: API health (`/readyz`) and the Alertmanager **Watchdog** alert. If Watchdog stops firing, your alerting pipeline is dead.
- **Pod health %**: healthy pods (Running and ready, or Completed) over total.
- **Pods, Alerts, Warnings tabs**: newest pods with a colored state dot, firing Alertmanager alerts, recent `Warning` events.
- **Filters**: namespace, problem pods only, alert severity.
- **Nodes**: ready count, NotReady nodes listed by name.
- **Multiple clusters**: one tab per kubeconfig.
- **Notifications**: desktop and Telegram, sent once when a problem starts and once when it resolves.
- **Settings UI**: clusters and Telegram from the widget, no file editing.
- **Auto-update**: daily, from this repo.

## Requirements

- KDE Plasma 6 or GNOME Shell 45 to 49
- `git`, `kubectl`, `jq`, `curl`, `notify-send` (libnotify), systemd
- kubeconfigs that already work with `kubectl`

Watchdog needs an Alertmanager service named `alertmanager` on port 9093 in the `monitoring` namespace (the kube-prometheus default). Clusters without one show Watchdog as `n/a`; everything else still works.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/anas1412/cluster-health/main/install.sh | bash
```

No root needed. The installer:

1. clones this repo to `~/.local/share/cluster-health`
2. installs the checker to `~/.local/bin/cluster-health`
3. starts two systemd user timers: checks every minute, updates daily
4. installs the KDE widget and/or the GNOME extension, depending on what is installed

Then put it in your panel:

| Desktop | Steps |
| --- | --- |
| KDE | Right-click the panel > **Add or Manage Widgets** > search **Cluster Health** > drag it onto the panel |
| GNOME | Log out and back in, then run `gnome-extensions enable cluster-health@anas.dev` |

## Setup

Open the widget and click the **gear icon** (KDE) or **Settings…** (GNOME).

### Clusters

One kubeconfig path per line. The file name becomes the tab name. Defaults to `$KUBECONFIG` or `~/.kube/config`.

```
~/.kube/prod.yml
~/.kube/staging.yml
```

### Telegram (optional)

1. Create a bot with [@BotFather](https://t.me/BotFather) and copy its token.
2. Send your bot any message.
3. Open `https://api.telegram.org/bot<TOKEN>/getUpdates` and copy `message.chat.id`.
4. Paste both into settings. On KDE, **Save and send test message** confirms it works.

## Notifications

Each problem is sent once when it starts and once when it resolves, never repeated.

| Problem | Notified |
| --- | --- |
| API unreachable (after one retry) | yes |
| Watchdog missing | yes |
| Node NotReady | yes |
| Pod health below `HEALTH_MIN` (default 95%) | yes |
| Pod in CrashLoopBackOff, or OOMKilled in the last hour | yes |
| New `critical` alert | yes |
| `warning` / `info` alerts, Warning events | widget only |

Every request has a 30s timeout and one retry. If the pod list can't be fetched, health shows `?` and nothing is sent, so a slow network does not cause false alarms.

Change the health threshold:

```bash
systemctl --user edit cluster-health.service
```

```ini
[Service]
Environment=HEALTH_MIN=90
```

## Widget

### Panel icon

| Icon | Meaning |
| --- | --- |
| 🟢 `99%` | all good (lowest pod health across clusters) |
| 🟠 `93%` | pod health below 95%, a critical alert, or a NotReady node |
| 🔴 `DOWN` | API unreachable or Watchdog missing |

### Pod states

| Dot | State |
| --- | --- |
| 🟢 | Running and ready |
| 🟠 | Pending, or Running but not ready |
| 🔴 | Failed, CrashLoopBackOff, ImagePull errors, OOMKilled |
| ⚪ | Completed |

### Filters

| Filter | Applies to |
| --- | --- |
| Namespace | all tabs |
| Problems only (🔴 and 🟠) | Pods |
| Severity: critical / warning / info | Alerts |

## Updates

Automatic. Once a day the update timer pulls `main`, reinstalls if anything changed, and shows a desktop notification. Checker changes apply on the next check; widget changes load after you log out and back in.

```bash
~/.local/share/cluster-health/install.sh --update              # update now
systemctl --user disable --now cluster-health-update.timer     # turn off auto-update
```

## Uninstall

```bash
~/.local/share/cluster-health/install.sh --uninstall
```

Removes the checker, timers, widget and extension. Settings in `~/.config/cluster-health` are kept.

## How it works

```
cluster-health.timer (every 60s)
  └─ cluster-health ──kubectl──> each cluster
       ├─ ~/.cache/cluster-health/status.json ──> KDE widget / GNOME extension (read only)
       └─ on change: notify-send + Telegram

cluster-health-update.timer (daily)
  └─ install.sh --update: git pull, reinstall if changed
```

The checker is plain bash and works on any desktop. The panel UIs only read `status.json`, so they never call the cluster themselves.

| Path | Content |
| --- | --- |
| `~/.config/cluster-health/clusters` | kubeconfig list |
| `~/.config/cluster-health/telegram.env` | `TG_TOKEN`, `TG_CHAT` (mode 600) |
| `~/.cache/cluster-health/status.json` | latest state of all clusters |
| `~/.local/share/cluster-health` | installed copy of this repo |

## Troubleshooting

```bash
cluster-health                                                       # run a check now
jq '.clusters[] | {name, up, watchdog, pct: .pods.pct}' ~/.cache/cluster-health/status.json
systemctl --user list-timers 'cluster-health*'
journalctl --user -u cluster-health.service -u cluster-health-update.service
```

| Symptom | Fix |
| --- | --- |
| Widget shows `?` | No status yet. Run `cluster-health`, then check that `kubectl` works with each kubeconfig. |
| Widget not in the Add Widgets list (KDE) | Run `systemctl --user restart plasma-plasmashell` |
| No Telegram messages | Use **Save and send test message**; check the bot token and that you messaged the bot first. |
| Watchdog `n/a` | The cluster has no `monitoring/alertmanager` service. |

## License

MIT
