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
    property int mutedUntil: 0
    property int current: 0
    property string nsFilter: ""
    property int section: 0
    property bool problemsOnly: false
    property string sevFilter: ""

    readonly property string bin: "\"$HOME/.local/bin/kube-health\""
    readonly property string loadCmd: "cat \"${XDG_CACHE_HOME:-$HOME/.cache}/kube-health/status.json\""

    function byNs(list) { return list.filter(x => !nsFilter || x.ns === nsFilter) }
    function bad(c) { return !c.up || c.watchdog === false }
    function pct(c) { return c.pods.pct === null || c.pods.pct === undefined ? "?" : c.pods.pct + "%" }
    function color(c) {
        if (bad(c)) return Kirigami.Theme.negativeTextColor
        if ((c.pods.pct ?? 100) < 95 || c.alerts.some(a => a.severity === "critical")
            || (c.nodes?.notready.length ?? 0) > 0) return Kirigami.Theme.neutralTextColor
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
    function muteText() {
        return mutedUntil === -1 ? "Muted until you unmute"
            : mutedUntil > 0 ? "Muted until " + new Date(mutedUntil * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
            : ""
    }
    // Worst cluster drives the panel icon.
    readonly property var worst: clusters.length ? clusters.slice().sort((a, b) =>
        (bad(b) - bad(a)) || ((a.pods.pct ?? 100) - (b.pods.pct ?? 100)))[0] : null

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
                    root.mutedUntil = s.muted_until ?? 0
                } catch (e) { root.clusters = [] }
            } else if (source.includes("#mute")) {
                root.load()
            }
        }
    }
    function load() { exec.connectSource(loadCmd) }
    function refresh() { exec.connectSource("systemctl --user start kube-health.service; true #refresh"); refreshTimer.start() }
    function mute(arg) { exec.connectSource(bin + " --mute " + arg + " #mute" + Date.now()) }
    Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.load() }
    Timer { id: refreshTimer; interval: 12000; onTriggered: root.load() }

    Plasmoid.icon: "kube-health"
    toolTipMainText: "Kube Health"
    toolTipSubText: clusters.map(c => `${c.name}: ${c.up ? pct(c) : "DOWN"}`).join("\n") + (mutedUntil ? "\n🔕 " + muteText() : "")

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
                text: !root.worst ? "?" : root.bad(root.worst) ? "DOWN" : root.pct(root.worst)
            }
            Kirigami.Icon {
                visible: root.mutedUntil !== 0
                source: "notifications-disabled"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
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
        readonly property var pods: c ? root.byNs(c.pods.recent)
            .filter(p => !root.problemsOnly || p.state === "bad" || p.state === "pending") : []
        readonly property var alerts: c ? root.byNs(c.alerts)
            .filter(a => !root.sevFilter || a.severity === root.sevFilter) : []
        readonly property var events: c ? root.byNs(c.events) : []

        RowLayout {
            PlasmaComponents.TabBar {
                Layout.fillWidth: true
                Repeater {
                    model: root.clusters
                    PlasmaComponents.TabButton {
                        text: (root.bad(modelData) ? "🔴 " : "") + modelData.name
                        onClicked: { root.current = index; root.nsFilter = "" }
                    }
                }
            }
            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                PlasmaComponents.ToolTip { text: "Check now" }
                onClicked: root.refresh()
            }
            PlasmaComponents.ToolButton {
                id: muteButton
                icon.name: root.mutedUntil ? "notifications-disabled" : "notifications"
                PlasmaComponents.ToolTip { text: root.mutedUntil ? root.muteText() : "Mute notifications" }
                onClicked: muteMenu.popup(muteButton, 0, muteButton.height)
                PlasmaComponents.Menu {
                    id: muteMenu
                    PlasmaComponents.MenuItem { text: "Unmute"; visible: root.mutedUntil !== 0; height: visible ? implicitHeight : 0; onTriggered: root.mute("off") }
                    PlasmaComponents.MenuItem { text: "Mute for 1 hour"; onTriggered: root.mute(3600) }
                    PlasmaComponents.MenuItem { text: "Mute for 4 hours"; onTriggered: root.mute(14400) }
                    PlasmaComponents.MenuItem { text: "Mute for 8 hours"; onTriggered: root.mute(28800) }
                    PlasmaComponents.MenuItem { text: "Mute for 24 hours"; onTriggered: root.mute(86400) }
                    PlasmaComponents.MenuItem { text: "Mute until I unmute"; onTriggered: root.mute("forever") }
                }
            }
            PlasmaComponents.ToolButton {
                icon.name: "configure"
                PlasmaComponents.ToolTip { text: "Settings" }
                onClicked: Plasmoid.internalAction("configure").trigger()
            }
        }

        PlasmaComponents.Label {
            visible: root.mutedUntil !== 0
            Layout.fillWidth: true
            text: "🔕 " + root.muteText() + ". Anything still broken is sent when the mute ends."
            opacity: 0.8
        }

        PlasmaComponents.Label {
            visible: !!c
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: !c ? "" : (c.up ? "API ✅" : "API 🔴 unreachable")
                + "   Watchdog " + (c.watchdog === null ? "n/a" : c.watchdog ? "✅" : "🔴 missing")
                + "   Pods " + c.pods.healthy + "/" + c.pods.total + " (" + root.pct(c) + ")"
                + (c.nodes ? "   Nodes " + (c.nodes.total - c.nodes.notready.length) + "/" + c.nodes.total
                    + (c.nodes.notready.length ? " 🟠 NotReady: " + c.nodes.notready.join(", ") : "") : "")
                + "   · " + root.updated.replace("T", " ").replace("Z", " UTC")
            color: c ? root.color(c) : Kirigami.Theme.textColor
        }

        RowLayout {
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

        RowLayout {
            visible: root.section !== 2
            PlasmaComponents.CheckBox {
                visible: root.section === 0
                text: "Problems only"
                checked: root.problemsOnly
                onToggled: root.problemsOnly = checked
            }
            PlasmaComponents.ComboBox {
                visible: root.section === 1
                readonly property var values: ["", "critical", "warning", "info"]
                model: ["All severities", "Critical", "Warning", "Info"]
                currentIndex: values.indexOf(root.sevFilter)
                onActivated: root.sevFilter = values[currentIndex]
            }
        }

        PlasmaComponents.ScrollView {
            id: scroll
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
