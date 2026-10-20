import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    property var clusters: []
    property string updated: ""
    property int current: 0
    property string nsFilter: ""
    property int section: 0
    property bool settingsOpen: false
    property string cfgClusters: ""
    property string cfgToken: ""
    property string cfgChat: ""
    property string cfgMsg: ""

    readonly property string confDir: "\"${XDG_CONFIG_HOME:-$HOME/.config}/cluster-health\""
    readonly property string loadCmd: "cat \"${XDG_CACHE_HOME:-$HOME/.cache}/cluster-health/status.json\""
    readonly property string cfgCmd: "d=" + confDir + "; jq -n --rawfile c \"$d/clusters\" --rawfile t \"$d/telegram.env\" '{c:$c,t:$t}'"

    function byNs(list) { return list.filter(x => !nsFilter || x.ns === nsFilter) }
    function bad(c) { return !c.up || c.watchdog === false }
    function color(c) {
        if (bad(c)) return Kirigami.Theme.negativeTextColor
        if (c.pods.pct < 95 || c.alerts.some(a => a.severity === "critical")) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.positiveTextColor
    }
    function stateColor(s) {
        return { ok: Kirigami.Theme.positiveTextColor, pending: Kirigami.Theme.neutralTextColor,
                 bad: Kirigami.Theme.negativeTextColor }[s] || Kirigami.Theme.disabledTextColor
    }
    function sevColor(s) {
        return { critical: Kirigami.Theme.negativeTextColor, warning: Kirigami.Theme.neutralTextColor }[s]
            || Kirigami.Theme.disabledTextColor
    }
    // Worst cluster drives the panel icon.
    readonly property var worst: clusters.length ? clusters.slice().sort((a, b) =>
        (bad(b) - bad(a)) || (a.pods.pct - b.pods.pct))[0] : null

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source)
            if (source === root.loadCmd) {
                try {
                    const s = JSON.parse(data.stdout)
                    root.clusters = s.clusters
                    root.updated = s.updated
                } catch (e) { root.clusters = [] }
            } else if (source === root.cfgCmd) {
                try {
                    const s = JSON.parse(data.stdout)
                    root.cfgClusters = s.c.trim()
                    const get = k => ((s.t.match(new RegExp("^" + k + "=(.*)$", "m")) || [])[1] || "").trim()
                    root.cfgToken = get("TG_TOKEN")
                    root.cfgChat = get("TG_CHAT")
                } catch (e) { root.cfgMsg = "Could not read settings" }
            } else if (source.includes("#test")) {
                root.cfgMsg = data.stdout.includes("\"ok\":true") ? "Test message sent" : "Telegram error: " + (data.stdout || data.stderr)
            }
        }
    }
    function load() { exec.connectSource(loadCmd) }
    function refresh() { exec.connectSource("systemctl --user start cluster-health.service; true #refresh"); refreshTimer.start() }
    function openSettings() { cfgMsg = ""; settingsOpen = true; exec.connectSource(cfgCmd) }
    function saveSettings(test) {
        // Values travel base64-encoded so nothing typed is ever interpreted by the shell.
        const b64 = s => Qt.btoa(unescape(encodeURIComponent(s)))
        const tg = "TG_TOKEN=" + cfgToken.trim() + "\nTG_CHAT=" + cfgChat.trim() + "\n"
        let cmd = "d=" + confDir + "; mkdir -p \"$d\""
            + "; echo " + b64(cfgClusters.trim() + "\n") + " | base64 -d > \"$d/clusters\""
            + "; (umask 077; echo " + b64(tg) + " | base64 -d > \"$d/telegram.env\")"
            + "; systemctl --user start cluster-health.service --no-block"
        if (test)
            cmd += "; . \"$d/telegram.env\"; curl -s -m 10 \"https://api.telegram.org/bot$TG_TOKEN/sendMessage\""
                + " --data-urlencode \"chat_id=$TG_CHAT\" --data-urlencode \"text=✅ Cluster Health test message\" #test" + Date.now()
        else
            cmd += " #save" + Date.now()
        cfgMsg = test ? "Sending…" : "Saved"
        exec.connectSource(cmd)
        refreshTimer.start()
    }
    Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.load() }
    Timer { id: refreshTimer; interval: 12000; onTriggered: root.load() }

    toolTipMainText: "Cluster Health"
    toolTipSubText: clusters.map(c => `${c.name}: ${c.up ? c.pods.pct + "%" : "DOWN"}`).join("\n")

    compactRepresentation: MouseArea {
        Layout.minimumWidth: row.implicitWidth
        onClicked: root.expanded = !root.expanded
        RowLayout {
            id: row
            anchors.fill: parent
            Rectangle {
                width: Kirigami.Units.iconSizes.small / 1.5; height: width; radius: width / 2
                color: root.worst ? root.color(root.worst) : Kirigami.Theme.disabledTextColor
            }
            PlasmaComponents.Label {
                text: !root.worst ? "?" : root.bad(root.worst) ? "DOWN" : root.worst.pods.pct + "%"
            }
        }
    }

    component Dot: Rectangle {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Kirigami.Units.smallSpacing
        width: Kirigami.Units.gridUnit / 2; height: width; radius: width / 2
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 36
        Layout.preferredHeight: Kirigami.Units.gridUnit * 32
        readonly property var c: root.clusters[root.current] || null
        readonly property var pods: c ? root.byNs(c.pods.recent) : []
        readonly property var alerts: c ? root.byNs(c.alerts) : []
        readonly property var events: c ? root.byNs(c.events) : []

        RowLayout {
            PlasmaComponents.TabBar {
                Layout.fillWidth: true
                visible: !root.settingsOpen
                Repeater {
                    model: root.clusters
                    PlasmaComponents.TabButton {
                        text: (root.bad(modelData) ? "🔴 " : "") + modelData.name
                        onClicked: { root.current = index; root.nsFilter = "" }
                    }
                }
            }
            Kirigami.Heading { Layout.fillWidth: true; level: 3; text: "Settings"; visible: root.settingsOpen }
            PlasmaComponents.ToolButton { icon.name: "view-refresh"; visible: !root.settingsOpen; onClicked: root.refresh() }
            PlasmaComponents.ToolButton {
                icon.name: root.settingsOpen ? "go-previous" : "configure"
                PlasmaComponents.ToolTip { text: root.settingsOpen ? "Back" : "Settings" }
                onClicked: root.settingsOpen ? (root.settingsOpen = false) : root.openSettings()
            }
        }

        // ---- Settings page ----
        ColumnLayout {
            visible: root.settingsOpen
            Layout.fillWidth: true
            Layout.fillHeight: true

            PlasmaComponents.Label { text: "Kubeconfig files, one path per line (tab name = file name):" }
            PlasmaComponents.ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 6
                PlasmaComponents.TextArea {
                    text: root.cfgClusters
                    placeholderText: "~/.kube/config"
                    font.family: "monospace"
                    onTextChanged: root.cfgClusters = text
                }
            }

            Kirigami.Heading { level: 4; text: "Telegram"; Layout.topMargin: Kirigami.Units.largeSpacing }
            PlasmaComponents.Label {
                Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.7
                text: "Create a bot with @BotFather, message it once, then get the chat id from api.telegram.org/bot<TOKEN>/getUpdates."
            }
            GridLayout {
                columns: 2
                Layout.fillWidth: true
                PlasmaComponents.Label { text: "Bot token" }
                PlasmaComponents.TextField {
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    text: root.cfgToken
                    onTextChanged: root.cfgToken = text
                }
                PlasmaComponents.Label { text: "Chat id" }
                PlasmaComponents.TextField {
                    Layout.fillWidth: true
                    text: root.cfgChat
                    onTextChanged: root.cfgChat = text
                }
            }

            RowLayout {
                Layout.topMargin: Kirigami.Units.largeSpacing
                PlasmaComponents.Button { text: "Save"; icon.name: "document-save"; onClicked: root.saveSettings(false) }
                PlasmaComponents.Button {
                    text: "Save and send test message"; icon.name: "mail-send"
                    enabled: root.cfgToken !== "" && root.cfgChat !== ""
                    onClicked: root.saveSettings(true)
                }
            }
            PlasmaComponents.Label { text: root.cfgMsg; Layout.fillWidth: true; wrapMode: Text.Wrap }
            Item { Layout.fillHeight: true }
        }

        // ---- Cluster view ----
        PlasmaComponents.Label {
            visible: !!c && !root.settingsOpen
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: !c ? "" : (c.up ? "API ✅" : "API 🔴 unreachable")
                + "   Watchdog " + (c.watchdog === null ? "n/a" : c.watchdog ? "✅" : "🔴 missing")
                + "   Pods " + c.pods.healthy + "/" + c.pods.total + " (" + c.pods.pct + "%)"
                + "   · " + root.updated.replace("T", " ").replace("Z", " UTC")
            color: c ? root.color(c) : Kirigami.Theme.textColor
        }

        RowLayout {
            visible: !root.settingsOpen
            PlasmaComponents.TabBar {
                Layout.fillWidth: true
                currentIndex: root.section
                PlasmaComponents.TabButton { text: "Pods (" + pods.length + ")"; onClicked: root.section = 0 }
                PlasmaComponents.TabButton { text: "Alerts (" + alerts.length + ")"; onClicked: root.section = 1 }
                PlasmaComponents.TabButton { text: "Warnings (" + events.length + ")"; onClicked: root.section = 2 }
            }
            PlasmaComponents.ComboBox {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                model: ["All namespaces"].concat(c ? c.pods.namespaces : [])
                onActivated: root.nsFilter = currentIndex === 0 ? "" : currentText
            }
        }

        PlasmaComponents.ScrollView {
            id: scroll
            visible: !root.settingsOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
            ColumnLayout {
                width: scroll.availableWidth

                PlasmaComponents.Label {
                    text: "Nothing here"; opacity: 0.6
                    visible: [pods, alerts, events][root.section].length === 0
                }
                Repeater {
                    model: root.section === 0 ? pods.slice(0, 50) : []
                    RowLayout {
                        Layout.fillWidth: true
                        Dot { color: root.stateColor(modelData.state) }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            color: modelData.state === "bad" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                            text: modelData.age + "  " + modelData.ns + "/" + modelData.name
                                + "  " + (modelData.reason || modelData.phase) + " " + modelData.ready
                                + (modelData.restarts ? "  ↻" + modelData.restarts : "")
                        }
                    }
                }
                Repeater {
                    model: root.section === 1 ? alerts : []
                    RowLayout {
                        Layout.fillWidth: true
                        Dot { color: root.sevColor(modelData.severity) }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true; wrapMode: Text.Wrap
                            text: "<b>" + modelData.name + "</b> " + modelData.ns + " · " + modelData.msg
                        }
                    }
                }
                Repeater {
                    model: root.section === 2 ? events : []
                    RowLayout {
                        Layout.fillWidth: true
                        Dot { color: Kirigami.Theme.neutralTextColor }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true; wrapMode: Text.Wrap
                            text: modelData.age + " <b>" + modelData.reason + "</b> " + modelData.ns + "/" + modelData.obj + " · " + modelData.msg
                        }
                    }
                }
            }
        }
    }
}
