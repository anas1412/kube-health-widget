import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support

// Settings live in ~/.config/kube-health (shared with GNOME); all reads and writes go through
// the kube-health command. Values are passed base64-encoded so nothing typed reaches the shell.
KCM.SimpleKCM {
    id: page
    signal configurationChanged

    readonly property string bin: "\"$HOME/.local/bin/kube-health\""
    readonly property string getCmd: bin + " --get"
    readonly property var mutes: [["Not muted", "off"], ["1 hour", "3600"], ["4 hours", "14400"], ["8 hours", "28800"],
                                  ["24 hours", "86400"], ["Until I unmute", "forever"]]
    // Notification rules: NOTIFY_<key>=0 turns one off. limit names the threshold setting shown next to it.
    readonly property var rules: [
        {key: "API", text: "A cluster API is unreachable"},
        {key: "WATCHDOG", text: "Watchdog is missing (alerting is down)"},
        {key: "CRITICAL", text: "A critical alert fires"},
        {key: "NODE_NOTREADY", text: "A node becomes NotReady"},
        {key: "NODE_PRESSURE", text: "A node has memory, disk or PID pressure"},
        {key: "NODE_CPU", text: "A node's CPU reaches", limit: "NODE_CPU_MAX", def: 90},
        {key: "NODE_MEM", text: "A node's RAM reaches", limit: "NODE_MEM_MAX", def: 90},
        {key: "POD_HEALTH", text: "Pod health drops below", limit: "HEALTH_MIN", def: 95},
        {key: "CRASHLOOP", text: "A pod is in CrashLoopBackOff or OOMKilled"},
        {key: "PIPELINES", text: "A pipeline fails (and when it is fixed)"}
    ]
    property var ruleOn: ({})
    property var limits: ({NODE_CPU_MAX: 90, NODE_MEM_MAX: 90, HEALTH_MIN: 95})
    property bool loading: true
    property int mutedUntil: 0
    property string testResult: ""

    // Repositories: allRepos comes from `kube-health --list-repos`, selectedRepos holds repo ids.
    readonly property string listCmd: bin + " --list-repos"
    property var allRepos: []
    property var selectedRepos: []
    property bool reposLoading: true
    property string repoSearch: ""
    // No search: the selected repos. Searching: the first 10 matches.
    readonly property var repoMatches: allRepos.filter(r => r.name.toLowerCase().includes(repoSearch))
    readonly property var repoModel: repoSearch ? repoMatches.slice(0, 10)
        : selectedRepos.map(id => allRepos.find(r => r.id === id)
            || {id: id, name: id.replace(/^[a-z]+:/, "").replace(/@.*$/, ""), source: id.split(":")[0]})
    function toggleRepo(id, on) {
        selectedRepos = on ? selectedRepos.concat([id]) : selectedRepos.filter(x => x !== id)
        changed()
    }
    function setRule(key, on) { const r = Object.assign({}, ruleOn); r[key] = on; ruleOn = r; changed() }
    function setLimit(key, v) { const l = Object.assign({}, limits); l[key] = v; limits = l; changed() }

    function b64(s) { return Qt.btoa(unescape(encodeURIComponent(s))) }
    function changed() { if (!loading) configurationChanged() }

    function settingsText() {
        return rules.map(r => "NOTIFY_" + r.key + "=" + (ruleOn[r.key] !== false ? 1 : 0))
            .concat(Object.keys(limits).map(k => k + "=" + limits[k]))
            .concat(["NOTIFY_DESKTOP=" + (desktop.checked ? 1 : 0),
                     "TG_TOKEN=" + tgToken.text.trim(), "TG_CHAT=" + tgChat.text.trim(),
                     "SLACK_WEBHOOK=" + slack.text.trim(), "MATTERMOST_WEBHOOK=" + mattermost.text.trim(),
                     "DISCORD_WEBHOOK=" + discord.text.trim()]).join("\n") + "\n"
    }
    function saveCmd() {
        let cmd = "echo " + b64(settingsText()) + " | base64 -d | " + bin + " --set -"
            + "; echo " + b64(clusters.text.trim() + "\n") + " | base64 -d | " + bin + " --clusters"
            + "; echo " + b64(selectedRepos.join("\n") + "\n") + " | base64 -d | " + bin + " --repos"
        if (mute.currentIndex > 0 || mutedUntil !== 0)
            cmd += "; " + bin + " --mute " + mutes[mute.currentIndex][1]
        return cmd + "; systemctl --user start kube-health.service --no-block"
    }
    function saveConfig() { exec.connectSource(saveCmd() + " #save" + Date.now()) }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        Component.onCompleted: { connectSource(page.getCmd); connectSource(page.listCmd) }
        onNewData: (source, data) => {
            disconnectSource(source)
            if (source === page.getCmd) {
                try {
                    const s = JSON.parse(data.stdout), v = s.settings
                    clusters.text = s.clusters.trim()
                    page.selectedRepos = s.repos || []
                    const on = {}
                    page.rules.forEach(r => on[r.key] = v["NOTIFY_" + r.key] !== "0")
                    page.ruleOn = on
                    page.limits = {NODE_CPU_MAX: parseInt(v.NODE_CPU_MAX || "90"), NODE_MEM_MAX: parseInt(v.NODE_MEM_MAX || "90"),
                                   HEALTH_MIN: parseInt(v.HEALTH_MIN || "95")}
                    desktop.checked = v.NOTIFY_DESKTOP !== "0"
                    tgToken.text = v.TG_TOKEN || ""
                    tgChat.text = v.TG_CHAT || ""
                    slack.text = v.SLACK_WEBHOOK || ""
                    mattermost.text = v.MATTERMOST_WEBHOOK || ""
                    discord.text = v.DISCORD_WEBHOOK || ""
                    page.mutedUntil = s.muted_until
                } catch (e) {
                    page.testResult = "Could not load settings. Is kube-health installed in ~/.local/bin?"
                }
                page.loading = false
            } else if (source === page.listCmd) {
                try { page.allRepos = JSON.parse(data.stdout) } catch (e) { page.allRepos = [] }
                page.reposLoading = false
            } else if (source.includes("#test")) {
                page.testResult = data.stdout.trim() || "No notification targets configured"
            }
        }
    }

    component Hint: QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 26
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }

    Kirigami.FormLayout {
        // ---- Clusters ----
        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Clusters" }

        QQC2.TextArea {
            id: clusters
            Kirigami.FormData.label: "Kubeconfig files:"
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 26
            Layout.minimumHeight: Kirigami.Units.gridUnit * 4
            font.family: "monospace"
            placeholderText: "~/.kube/config"
            onTextChanged: page.changed()
        }
        Hint {
            text: "One per line; the file name becomes the tab name. Alertmanager is detected automatically. "
                + "To set it by hand, add it after the path: ~/.kube/prod.yml monitoring/alertmanager:9093"
        }

        // ---- CI pipelines ----
        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "CI pipelines" }

        Kirigami.SearchField {
            Kirigami.FormData.label: "Add repositories:"
            Layout.fillWidth: true
            placeholderText: page.reposLoading ? "Loading repositories from gh and glab…"
                                               : "Search " + page.allRepos.length + " repositories"
            onTextChanged: page.repoSearch = text.trim().toLowerCase()
        }
        ColumnLayout {
            Kirigami.FormData.label: page.repoSearch ? "Matches:" : "Tracked (" + page.selectedRepos.length + "):"
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: page.repoModel
                QQC2.CheckBox {
                    required property var modelData
                    text: modelData.name + "   ·   " + modelData.source + ", " + modelData.id.split("@").pop()
                    checked: page.selectedRepos.includes(modelData.id)
                    onToggled: page.toggleRepo(modelData.id, checked)
                }
            }
            QQC2.Label {
                visible: text !== ""
                opacity: 0.7
                text: page.repoSearch
                    ? (page.repoMatches.length === 0 ? (page.reposLoading ? "Still loading…" : "No matches")
                       : page.repoMatches.length > 10 ? (page.repoMatches.length - 10) + " more, refine your search" : "")
                    : (page.selectedRepos.length === 0 ? "None yet. Search above to add repositories." : "")
            }
        }
        Hint { text: "Lists what your gh (GitHub) and glab (GitLab) logins can see. Each repo is tracked on its default branch." }

        // ---- What to notify about ----
        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Notifications" }

        ColumnLayout {
            Kirigami.FormData.label: "Notify me when:"
            spacing: 0
            Repeater {
                model: page.rules
                RowLayout {
                    required property var modelData
                    QQC2.CheckBox {
                        id: ruleBox
                        text: modelData.text
                        checked: page.ruleOn[modelData.key] !== false
                        onToggled: page.setRule(modelData.key, checked)
                    }
                    QQC2.SpinBox {
                        visible: !!modelData.limit
                        enabled: ruleBox.checked
                        from: 1; to: 100
                        value: modelData.limit ? (page.limits[modelData.limit] ?? modelData.def) : 0
                        textFromValue: v => v + "%"
                        valueFromText: t => parseInt(t)
                        onValueModified: page.setLimit(modelData.limit, value)
                    }
                }
            }
        }
        Hint {
            text: "Each problem is sent once when it starts and once when it is resolved. "
                + "Node CPU and RAM only count as resolved 5 points below the limit, so a node at the edge does not flap."
        }

        // ---- Delivery ----
        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Delivery" }

        QQC2.CheckBox {
            id: desktop
            Kirigami.FormData.label: "Desktop:"
            text: "Show desktop notifications"
            onToggled: page.changed()
        }
        RowLayout {
            Kirigami.FormData.label: "Mute:"
            QQC2.ComboBox {
                id: mute
                model: page.mutes.map(m => m[0])
                onActivated: page.changed()
            }
            QQC2.Label {
                opacity: 0.7
                text: page.mutedUntil === -1 ? "Muted until unmuted"
                    : page.mutedUntil > 0 ? "Muted until " + new Date(page.mutedUntil * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                    : ""
            }
        }

        Kirigami.PasswordField {
            id: tgToken
            Kirigami.FormData.label: "Telegram bot token:"
            Layout.fillWidth: true
            placeholderText: "from @BotFather"
            onTextChanged: page.changed()
        }
        QQC2.TextField {
            id: tgChat
            Kirigami.FormData.label: "Telegram chat id:"
            Layout.fillWidth: true
            placeholderText: "message.chat.id from api.telegram.org/bot<TOKEN>/getUpdates"
            onTextChanged: page.changed()
        }
        Kirigami.PasswordField {
            id: slack
            Kirigami.FormData.label: "Slack webhook:"
            Layout.fillWidth: true
            placeholderText: "https://hooks.slack.com/services/…"
            onTextChanged: page.changed()
        }
        Kirigami.PasswordField {
            id: mattermost
            Kirigami.FormData.label: "Mattermost webhook:"
            Layout.fillWidth: true
            placeholderText: "https://mattermost.example.com/hooks/…"
            onTextChanged: page.changed()
        }
        Kirigami.PasswordField {
            id: discord
            Kirigami.FormData.label: "Discord webhook:"
            Layout.fillWidth: true
            placeholderText: "https://discord.com/api/webhooks/…"
            onTextChanged: page.changed()
        }
        Hint { text: "Messages are sent from this computer, so they stop while it is off or asleep." }

        RowLayout {
            QQC2.Button {
                text: "Save and send test message"
                icon.name: "mail-send"
                onClicked: {
                    page.testResult = "Sending…"
                    exec.connectSource(page.saveCmd() + "; " + page.bin + " --test #test" + Date.now())
                }
            }
        }
        QQC2.Label {
            visible: page.testResult !== ""
            text: page.testResult
            font.family: "monospace"
        }
    }
}
