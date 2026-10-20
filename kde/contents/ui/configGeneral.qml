import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support

// Settings live in ~/.config/cluster-health (shared with GNOME); all reads and writes go through
// the cluster-health command. Values are passed base64-encoded so nothing typed reaches the shell.
KCM.SimpleKCM {
    id: page
    signal configurationChanged

    readonly property string bin: "\"$HOME/.local/bin/cluster-health\""
    readonly property string getCmd: bin + " --get"
    readonly property var mutes: [["Not muted", "off"], ["1 hour", "3600"], ["4 hours", "14400"], ["8 hours", "28800"],
                                  ["24 hours", "86400"], ["Until I unmute", "forever"]]
    property bool loading: true
    property int mutedUntil: 0
    property string testResult: ""

    function b64(s) { return Qt.btoa(unescape(encodeURIComponent(s))) }
    function changed() { if (!loading) configurationChanged() }

    function settingsText() {
        return ["NOTIFY_DESKTOP=" + (desktop.checked ? 1 : 0), "HEALTH_MIN=" + healthMin.value,
                "TG_TOKEN=" + tgToken.text.trim(), "TG_CHAT=" + tgChat.text.trim(),
                "SLACK_WEBHOOK=" + slack.text.trim(), "MATTERMOST_WEBHOOK=" + mattermost.text.trim(),
                "DISCORD_WEBHOOK=" + discord.text.trim()].join("\n") + "\n"
    }
    function saveCmd() {
        let cmd = "echo " + b64(settingsText()) + " | base64 -d | " + bin + " --set -"
            + "; echo " + b64(clusters.text.trim() + "\n") + " | base64 -d | " + bin + " --clusters"
        if (mute.currentIndex > 0 || mutedUntil !== 0)
            cmd += "; " + bin + " --mute " + mutes[mute.currentIndex][1]
        return cmd + "; systemctl --user start cluster-health.service --no-block"
    }
    function saveConfig() { exec.connectSource(saveCmd() + " #save" + Date.now()) }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        Component.onCompleted: connectSource(page.getCmd)
        onNewData: (source, data) => {
            disconnectSource(source)
            if (source === page.getCmd) {
                try {
                    const s = JSON.parse(data.stdout), v = s.settings
                    clusters.text = s.clusters.trim()
                    desktop.checked = v.NOTIFY_DESKTOP !== "0"
                    healthMin.value = parseInt(v.HEALTH_MIN || "95")
                    tgToken.text = v.TG_TOKEN || ""
                    tgChat.text = v.TG_CHAT || ""
                    slack.text = v.SLACK_WEBHOOK || ""
                    mattermost.text = v.MATTERMOST_WEBHOOK || ""
                    discord.text = v.DISCORD_WEBHOOK || ""
                    page.mutedUntil = s.muted_until
                } catch (e) {
                    page.testResult = "Could not load settings. Is cluster-health installed in ~/.local/bin?"
                }
                page.loading = false
            } else if (source.includes("#test")) {
                page.testResult = data.stdout.trim() || "No notification targets configured"
            }
        }
    }

    Kirigami.FormLayout {
        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Clusters" }

        QQC2.TextArea {
            id: clusters
            Kirigami.FormData.label: "Kubeconfig files:"
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 24
            Layout.minimumHeight: Kirigami.Units.gridUnit * 5
            font.family: "monospace"
            placeholderText: "~/.kube/config"
            onTextChanged: page.changed()
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: "One per line; the file name becomes the tab name. Alertmanager is detected automatically. "
                + "To set it by hand, add it after the path: ~/.kube/prod.yml monitoring/alertmanager:9093"
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Notifications" }

        QQC2.CheckBox {
            id: desktop
            Kirigami.FormData.label: "Desktop:"
            text: "Show desktop notifications"
            onToggled: page.changed()
        }
        QQC2.SpinBox {
            id: healthMin
            Kirigami.FormData.label: "Notify when pod health is below:"
            from: 0; to: 100
            textFromValue: v => v + "%"
            valueFromText: t => parseInt(t)
            onValueModified: page.changed()
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

        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Telegram" }

        Kirigami.PasswordField {
            id: tgToken
            Kirigami.FormData.label: "Bot token:"
            Layout.fillWidth: true
            placeholderText: "from @BotFather"
            onTextChanged: page.changed()
        }
        QQC2.TextField {
            id: tgChat
            Kirigami.FormData.label: "Chat id:"
            Layout.fillWidth: true
            placeholderText: "message.chat.id from api.telegram.org/bot<TOKEN>/getUpdates"
            onTextChanged: page.changed()
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Webhooks" }

        Kirigami.PasswordField {
            id: slack
            Kirigami.FormData.label: "Slack:"
            Layout.fillWidth: true
            placeholderText: "https://hooks.slack.com/services/…"
            onTextChanged: page.changed()
        }
        Kirigami.PasswordField {
            id: mattermost
            Kirigami.FormData.label: "Mattermost:"
            Layout.fillWidth: true
            placeholderText: "https://mattermost.example.com/hooks/…"
            onTextChanged: page.changed()
        }
        Kirigami.PasswordField {
            id: discord
            Kirigami.FormData.label: "Discord:"
            Layout.fillWidth: true
            placeholderText: "https://discord.com/api/webhooks/…"
            onTextChanged: page.changed()
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: "Messages are sent from this computer, so they stop while it is off or asleep."
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true }

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
