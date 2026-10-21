<p align="center"><img src="icons/kube-health.svg" width="96" alt=""></p>

# kube-health-widget

Kubernetes cluster health in your desktop panel: a KDE Plasma 6 widget and a GNOME Shell 45+ extension, with desktop, Telegram, Slack, Mattermost and Discord alerts.

```bash
curl -fsSL https://raw.githubusercontent.com/anas1412/kube-health-widget/main/install.sh | bash
```

## Features

- **Down detection**: API health (`/readyz`) and the Alertmanager **Watchdog** alert. If Watchdog stops firing, your alerting pipeline is dead. Alertmanager is found automatically.
- **Pod health %**: healthy pods (Running and ready, or Completed) over total.
- **Nodes, Pods, Alerts, Warnings tabs**: CPU and RAM per node, newest pods with a colored state dot, firing Alertmanager alerts, recent `Warning` events.
- **Filters**: namespace, problems only, alert severity.
- **Multiple clusters**: pick one from a dropdown.
- **CI pipelines**: latest GitHub Actions / GitLab CI status of the repos you pick, with commit and a link to the run.
- **Notifications**: desktop, Telegram, Slack, Mattermost, Discord. Sent once when a problem starts and once when it resolves. Every rule can be turned off and has its own threshold where it makes sense.
- **Mute**: for 1, 4, 8 or 24 hours, or until you unmute. You get a catch-up message when it ends.
- **Settings UI**: everything is configurable from the widget, no file editing.
- **Auto-update**: daily, from this repo.
- **The widget is the app**: checks and alerts run while the widget is on a panel. Remove it and everything stops. Background checking for chat alerts is an opt-in setting.

## Requirements

- KDE Plasma 6 or GNOME Shell 45 to 49
- `git`, `kubectl`, `jq`, `curl`, `notify-send` (libnotify), systemd
- kubeconfigs that already work with `kubectl`
- for node CPU and RAM: [metrics-server](https://github.com/kubernetes-sigs/metrics-server) on the cluster (nodes show "no metrics" without it)
- optional, for CI pipelines: [`gh`](https://cli.github.com) and/or [`glab`](https://gitlab.com/gitlab-org/cli), logged in

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/anas1412/kube-health-widget/main/install.sh | bash
```

No root needed. The installer:

1. clones this repo to `~/.local/share/kube-health`
2. installs the checker to `~/.local/bin/kube-health`
3. installs the KDE widget and/or the GNOME extension, depending on what is installed

Nothing runs until you put the widget on your panel; from then on it checks every minute:

| Desktop | Steps |
| --- | --- |
| KDE | Right-click the panel > **Add or Manage Widgets** > search **Kube Health** > drag it onto the panel |
| GNOME | Log out and back in, then run `gnome-extensions enable kube-health@anas1412.github.io` |

Removing the widget from the panel (or disabling the GNOME extension) stops all checks, alerts and updates. The files stay installed until you [uninstall](#uninstall).

### Background checking (optional)

Want alerts in Telegram or Slack even when the widget isn't on screen? Turn on **Keep checking when the widget is not on a panel** in settings. That starts a systemd user timer that runs the same check every minute until you turn it off or uninstall. With the widget on screen too, they share one check per minute.

## Settings

| Desktop | Open settings |
| --- | --- |
| KDE | Gear icon in the widget, or right-click the widget > **Configure Kube Health** |
| GNOME | **Settings…** in the menu, or the Extensions app |

Both write the same files, so settings carry over between desktops.

| Setting | Notes |
| --- | --- |
| Kubeconfig files | One per line. The file name is the cluster's name. Default: `$KUBECONFIG` or `~/.kube/config` |
| CI pipelines | Repos to track. See [CI pipelines](#ci-pipelines) |
| Notify me when | One switch per rule, with thresholds. See [Notifications](#notifications) |
| Desktop notifications | On by default |
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

### CI pipelines

In settings, search the repos your `gh` and `glab` logins can see and tick the ones to track. With an empty search the list shows only tracked repos.

| Setting | Default | |
| --- | --- | --- |
| Branches | the default branch | Comma-separated per repo, e.g. `main, develop`. Each branch gets its own row. |
| Recent runs per repo | 5 | Last N commits on the branch with their status. 0 hides them. |
| Merge / pull requests | on | Open MRs (GitLab) and PRs (GitHub) with their pipeline status. |

Switch the widget to **Pipelines** at the top. Each repo row shows the latest run of its branch; click the row to expand its recent runs and open MRs/PRs, and click any run or MR/PR to open it in your browser. The switch shows a badge with failed and running counts, e.g. `Pipelines 🔴 1 🔵 2`.

Notifications only cover tracked branches, not MR/PR pipelines, which fail often during review.

| Dot | Status |
| --- | --- |
| 🟢 | passed |
| 🔵 | running or queued |
| 🔴 | failed |
| ⚪ | canceled, no pipelines yet, or could not fetch |

On GitHub, all workflows of the latest commit are combined: one failed workflow makes the commit red.

Notifications use the last **finished** pipeline. A failed branch that is re-running shows as 🔵 running with "(last run failed)", but you only get ✅ once a run actually passes, so a retry that fails again doesn't send a false "fixed" and a second "failed".

Self-hosted GitLab works too: add `gitlab:gitlab.example.com/group/project@main` to `~/.config/kube-health/repos` (glab must be logged in to that host).

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

Each problem is sent once when it starts and once when it resolves, never repeated. All rules are on by default; turn any of them off under **Notify me when** in settings.

| Rule | Threshold | Setting |
| --- | --- | --- |
| A cluster API is unreachable (after one retry) | | `NOTIFY_API` |
| Watchdog is missing | | `NOTIFY_WATCHDOG` |
| A critical alert fires | | `NOTIFY_CRITICAL` |
| A node becomes NotReady | | `NOTIFY_NODE_NOTREADY` |
| A node has MemoryPressure, DiskPressure or PIDPressure | | `NOTIFY_NODE_PRESSURE` |
| A node's CPU reaches the limit | 90% (`NODE_CPU_MAX`) | `NOTIFY_NODE_CPU` |
| A node's RAM reaches the limit | 90% (`NODE_MEM_MAX`) | `NOTIFY_NODE_MEM` |
| Pod health drops below the limit | 95% (`HEALTH_MIN`) | `NOTIFY_POD_HEALTH` |
| A pod is in CrashLoopBackOff, or OOMKilled in the last hour | | `NOTIFY_CRASHLOOP` |
| A pipeline fails (last finished run) | | `NOTIFY_PIPELINES` |

`warning` / `info` alerts and Warning events show in the widget only.

Node CPU and RAM only count as resolved once they drop 5 points below the limit, so a node hovering at the edge doesn't send a new alert every minute.

Every request has a 30s timeout and one retry. If the pod list can't be fetched, health shows `?` and nothing is sent, so a slow network does not cause false alarms.

The first check after installing only records the current state, so you are not flooded with problems that already existed.

### Mute

Use the bell button in the widget (KDE), **Mute notifications** in the menu (GNOME), or the Mute setting. Choose 1, 4, 8 or 24 hours, or until you unmute.

While muted, the widget keeps updating and shows 🔕, but nothing is sent. When the mute ends you get one catch-up message: problems that started during the mute and are still active, and problems that were resolved.

## Widget

```
[ Clusters ]  [ Pipelines 🔴 1 🔵 2 ]                 ⟳  🔔  ⚙
[ prod ▾ ]   API ✅  Watchdog ✅  Pods 99%  Nodes 15/15
[ Nodes ]  [ Pods ]  [ Alerts ]  [ Warnings ]     [ All namespaces ▾ ]
```

### Panel icon

| Icon | Meaning |
| --- | --- |
| 🟢 `99%` | all good (lowest pod health across clusters) |
| 🟠 `93%` | pod health below the limit, a critical alert, or a node with a problem |
| 🔴 `DOWN` | API unreachable or Watchdog missing |
| 🔕 | notifications muted |

### Nodes

Each node shows its pool, pods running / pod capacity, and CPU and RAM bars with used / total. Problem nodes are listed first, then the busiest.

| Dot | State |
| --- | --- |
| 🟢 | Ready, below the CPU and RAM limits |
| 🟠 | Pressure condition, or CPU or RAM at the limit |
| 🔴 | NotReady |

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
| Namespace | Pods, Alerts, Warnings |
| Problems only (🔴 and 🟠) | Nodes, Pods |
| Severity: critical / warning / info | Alerts |

## Updates

Automatic while checks are running: once a day the checker pulls `main`, reinstalls if anything changed, and shows a desktop notification. Checker changes apply on the next check; widget changes load after you log out and back in. Turn it off with **Update automatically once a day** in settings.

```bash
~/.local/share/kube-health/install.sh --update     # update now
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
kube-health --background on        # keep checking without the widget (off to stop)
kube-health --mute 3600            # mute for 1 hour (seconds), or: --mute forever, --mute off
kube-health --set HEALTH_MIN=90    # change a setting
kube-health --get                  # print all settings as JSON
kube-health --list-repos           # repos your gh and glab logins can see
```

Setting keys: the `NOTIFY_*` rules and thresholds from [Notifications](#notifications), plus `PIPE_HISTORY`, `PIPE_MRS`, `BACKGROUND`, `AUTO_UPDATE`, `NOTIFY_DESKTOP`, `TG_TOKEN`, `TG_CHAT`, `SLACK_WEBHOOK`, `MATTERMOST_WEBHOOK`, `DISCORD_WEBHOOK`, `MUTE_UNTIL`.

## How it works

```
KDE widget / GNOME extension, every 60s while on screen
(or kube-health.timer, only with background checking on)
  └─ kube-health --if-stale 50 ──kubectl, gh, glab──> clusters and repos
       ├─ ~/.cache/kube-health/status.json ──> widget reads it every 15s
       ├─ on change, unless muted: desktop, Telegram, Slack, Mattermost, Discord
       └─ once a day: install.sh --update (git pull, reinstall if changed)
```

The checker is plain bash and works on any desktop. One check runs at a time (a lock file), and `--if-stale 50` skips a run if another one finished under 50 seconds ago, so two widgets, or a widget plus the background timer, still mean one check per minute. **Check now** waits for a running check and then runs a fresh one.

| Path | Content |
| --- | --- |
| `~/.config/kube-health/clusters` | kubeconfig list |
| `~/.config/kube-health/repos` | tracked repos, one `github:owner/repo@branch` or `gitlab:path@branch` per line |
| `~/.config/kube-health/settings.env` | settings and secrets (mode 600, read as text, never executed) |
| `~/.cache/kube-health/status.json` | latest state of all clusters |
| `~/.cache/kube-health/notified` | problems already notified |
| `~/.local/share/kube-health` | installed copy of this repo |

## Troubleshooting

```bash
jq '.clusters[] | {name, up, watchdog, alertmanager, pct: .pods.pct}' ~/.cache/kube-health/status.json
systemctl --user list-timers 'kube-health*'          # only with background checking on
journalctl --user -u kube-health.service
```

| Symptom | Fix |
| --- | --- |
| Widget shows `?` | No status yet. Run `kube-health`, then check that `kubectl` works with each kubeconfig. |
| Widget not in the Add Widgets list (KDE) | Run `systemctl --user restart plasma-plasmashell` |
| A target gets no messages | Use **Save and send test message**; it shows the error for each target. |
| Watchdog `n/a` | No Alertmanager found. Set it by hand in the clusters list. |
| Alerts keep coming after removing the widget | Background checking is on. Turn it off in settings, or run `kube-health --background off`. |

## License

MIT
