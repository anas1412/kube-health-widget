<p align="center"><img src="icons/kube-health.svg" width="96" alt=""></p>

# kube-health-widget

Kubernetes cluster health in your desktop panel: a KDE Plasma 6 widget and a GNOME Shell 45+ extension, with desktop, Telegram, Slack, Mattermost and Discord alerts.

```bash
curl -fsSL https://raw.githubusercontent.com/anas1412/kube-health-widget/main/install.sh | bash
```

## Features

- **Down detection**: API health (`/readyz`) and the Alertmanager **Watchdog** alert. If Watchdog stops firing, your alerting pipeline is dead. Alertmanager is found automatically.
- **Pod health %**: healthy pods (Running and ready, or Completed) over total.
- **Pods, Alerts, Warnings tabs**: newest pods with a colored state dot, firing Alertmanager alerts, recent `Warning` events.
- **Filters**: namespace, problem pods only, alert severity.
- **Nodes**: ready count, NotReady nodes listed by name.
- **Multiple clusters**: one tab per kubeconfig.
- **Notifications**: desktop, Telegram, Slack, Mattermost, Discord. Sent once when a problem starts and once when it resolves.
- **Mute**: for 1, 4, 8 or 24 hours, or until you unmute. You get a catch-up message when it ends.
- **Settings UI**: everything is configurable from the widget, no file editing.
- **Auto-update**: daily, from this repo.

## Requirements

- KDE Plasma 6 or GNOME Shell 45 to 49
- `git`, `kubectl`, `jq`, `curl`, `notify-send` (libnotify), systemd
- kubeconfigs that already work with `kubectl`

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/anas1412/kube-health-widget/main/install.sh | bash
```

No root needed. The installer:

1. clones this repo to `~/.local/share/kube-health`
2. installs the checker to `~/.local/bin/kube-health`
3. starts two systemd user timers: checks every minute, updates daily
4. installs the KDE widget and/or the GNOME extension, depending on what is installed

Then put it in your panel:

| Desktop | Steps |
| --- | --- |
| KDE | Right-click the panel > **Add or Manage Widgets** > search **Kube Health** > drag it onto the panel |
| GNOME | Log out and back in, then run `gnome-extensions enable kube-health@anas1412.github.io` |

## Settings

| Desktop | Open settings |
| --- | --- |
| KDE | Gear icon in the widget, or right-click the widget > **Configure Kube Health** |
| GNOME | **Settings…** in the menu, or the Extensions app |

Both write the same files, so settings carry over between desktops.

| Setting | Notes |
| --- | --- |
| Kubeconfig files | One per line. The file name becomes the tab name. Default: `$KUBECONFIG` or `~/.kube/config` |
| Desktop notifications | On by default |
| Pod health threshold | Notify below this %, default 95 |
| Mute | See [Mute](#mute) |
| Telegram | Bot token and chat id |
| Slack, Mattermost, Discord | Incoming webhook URLs |

**Save and send test message** saves, then sends a test to every configured target and shows the result for each.

### Alertmanager

Found automatically on each cluster: a service labeled `app.kubernetes.io/name=alertmanager`, the operator's `alertmanager-operated` service, or a service named `alertmanager`, in any namespace. Clusters without one show Watchdog as `n/a`; everything else still works.

To set it by hand, add `namespace/service:port` after the kubeconfig path:

```
~/.kube/prod.yml     monitoring/alertmanager:9093
~/.kube/staging.yml
```

### Telegram

1. Create a bot with [@BotFather](https://t.me/BotFather) and copy its token.
2. Send your bot any message.
3. Open `https://api.telegram.org/bot<TOKEN>/getUpdates` and copy `message.chat.id`.
4. Paste both into settings.

### Slack, Mattermost, Discord

Create an incoming webhook in the channel you want, then paste its URL into settings.

| Service | Where |
| --- | --- |
| Slack | [api.slack.com/apps](https://api.slack.com/apps) > your app > **Incoming Webhooks** > **Add New Webhook to Workspace** |
| Mattermost | **Integrations** > **Incoming Webhooks** > **Add Incoming Webhook** |
| Discord | Channel settings > **Integrations** > **Webhooks** > **New Webhook** > **Copy Webhook URL** |

Messages are sent from your computer, so they stop while it is off or asleep. For team-wide 24/7 alerts, configure Alertmanager's own Slack or Mattermost receiver on the cluster instead.

## Notifications

Each problem is sent once when it starts and once when it resolves, never repeated.

| Problem | Notified |
| --- | --- |
| API unreachable (after one retry) | yes |
| Watchdog missing | yes |
| Node NotReady | yes |
| Pod health below the threshold | yes |
| Pod in CrashLoopBackOff, or OOMKilled in the last hour | yes |
| New `critical` alert | yes |
| `warning` / `info` alerts, Warning events | widget only |

Every request has a 30s timeout and one retry. If the pod list can't be fetched, health shows `?` and nothing is sent, so a slow network does not cause false alarms.

The first check after installing only records the current state, so you are not flooded with problems that already existed.

### Mute

Use the bell button in the widget (KDE), **Mute notifications** in the menu (GNOME), or the Mute setting. Choose 1, 4, 8 or 24 hours, or until you unmute.

While muted, the widget keeps updating and shows 🔕, but nothing is sent. When the mute ends you get one catch-up message: problems that started during the mute and are still active, and problems that were resolved.

## Widget

### Panel icon

| Icon | Meaning |
| --- | --- |
| 🟢 `99%` | all good (lowest pod health across clusters) |
| 🟠 `93%` | pod health below 95%, a critical alert, or a NotReady node |
| 🔴 `DOWN` | API unreachable or Watchdog missing |
| 🔕 | notifications muted |

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
~/.local/share/kube-health/install.sh --update              # update now
systemctl --user disable --now kube-health-update.timer     # turn off auto-update
```

## Uninstall

```bash
~/.local/share/kube-health/install.sh --uninstall
```

Removes the checker, timers, widget, extension and icon. Settings in `~/.config/kube-health` are kept.

## Command line

```bash
kube-health                        # run a check now
kube-health --test                 # send a test message to every configured target
kube-health --mute 3600            # mute for 1 hour (seconds), or: --mute forever, --mute off
kube-health --set HEALTH_MIN=90    # change a setting
kube-health --get                  # print all settings as JSON
```

Setting keys: `NOTIFY_DESKTOP`, `HEALTH_MIN`, `TG_TOKEN`, `TG_CHAT`, `SLACK_WEBHOOK`, `MATTERMOST_WEBHOOK`, `DISCORD_WEBHOOK`, `MUTE_UNTIL`.

## How it works

```
kube-health.timer (every 60s)
  └─ kube-health ──kubectl──> each cluster
       ├─ ~/.cache/kube-health/status.json ──> KDE widget / GNOME extension (read only)
       └─ on change, unless muted: desktop, Telegram, Slack, Mattermost, Discord

kube-health-update.timer (daily)
  └─ install.sh --update: git pull, reinstall if changed
```

The checker is plain bash and works on any desktop. The panel UIs read `status.json` and change settings only through the `kube-health` command, so they never call the cluster themselves.

| Path | Content |
| --- | --- |
| `~/.config/kube-health/clusters` | kubeconfig list |
| `~/.config/kube-health/settings.env` | settings and secrets (mode 600, read as text, never executed) |
| `~/.cache/kube-health/status.json` | latest state of all clusters |
| `~/.cache/kube-health/notified` | problems already notified |
| `~/.local/share/kube-health` | installed copy of this repo |

## Troubleshooting

```bash
jq '.clusters[] | {name, up, watchdog, alertmanager, pct: .pods.pct}' ~/.cache/kube-health/status.json
systemctl --user list-timers 'kube-health*'
journalctl --user -u kube-health.service -u kube-health-update.service
```

| Symptom | Fix |
| --- | --- |
| Widget shows `?` | No status yet. Run `kube-health`, then check that `kubectl` works with each kubeconfig. |
| Widget not in the Add Widgets list (KDE) | Run `systemctl --user restart plasma-plasmashell` |
| A target gets no messages | Use **Save and send test message**; it shows the error for each target. |
| Watchdog `n/a` | No Alertmanager found. Set it by hand in the clusters list. |

## License

MIT
