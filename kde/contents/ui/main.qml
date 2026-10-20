import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    property var clusters: []
    property var pipelines: []
    property var thresholds: ({node_cpu: 90, node_mem: 90, health: 95})
    property string updated: ""
    property int mutedUntil: 0
    property string view: "clusters"   // or "pipelines"
    property int current: 0            // selected cluster
    property string nsFilter: ""
    property int section: 0            // 0 Nodes, 1 Pods, 2 Alerts, 3 Warnings
    property bool problemsOnly: false
    property string sevFilter: ""
    property var expanded: ({})         // pipeline id -> true when its row is expanded
    function toggleExpanded(id) { const e = Object.assign({}, expanded); e[id] = !e[id]; expanded = e }

    readonly property string bin: "\"$HOME/.local/bin/kube-health\""
    readonly property string loadCmd: "cat \"${XDG_CACHE_HOME:-$HOME/.cache}/kube-health/status.json\""

    readonly property bool showPipelines: (view === "pipelines" && pipelines.length > 0) || (clusters.length === 0 && pipelines.length > 0)
    readonly property int pipesFailed: pipelines.filter(p => p.status === "failed").length
    readonly property int pipesRunning: pipelines.filter(p => p.status === "running" || p.status === "pending").length
    function pipeColor(s) {
        return { passed: Kirigami.Theme.positiveTextColor, failed: Kirigami.Theme.negativeTextColor,
                 running: Kirigami.Theme.highlightColor, pending: Kirigami.Theme.highlightColor }[s]
            || Kirigami.Theme.disabledTextColor
    }
    function pipeText(s) {
        return { passed: "passed", failed: "failed", running: "running", pending: "pending", canceled: "canceled",
                 none: "no pipelines", error: "could not fetch" }[s] || s
    }

    function byNs(list) { return list.filter(x => !nsFilter || x.ns === nsFilter) }
    function bad(c) { return !c.up || c.watchdog === false }
    function pct(c) { return c.pods.pct === null || c.pods.pct === undefined ? "?" : c.pods.pct + "%" }
    function nodeState(n) {
        if (!n.ready) return "bad"
        if (n.pressure.length || (n.cpu_pct ?? 0) >= thresholds.node_cpu || (n.mem_pct ?? 0) >= thresholds.node_mem) return "pending"
        return "ok"
    }
    function color(c) {
        if (bad(c)) return Kirigami.Theme.negativeTextColor
        if ((c.pods.pct ?? 100) < thresholds.health || c.alerts.some(a => a.severity === "critical")
            || (c.nodes?.list ?? []).some(n => nodeState(n) !== "ok")) return Kirigami.Theme.neutralTextColor
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
    function gib(b) { return (b / 1073741824).toFixed(1) }
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
                    root.pipelines = s.pipelines ?? []
                    root.thresholds = s.thresholds ?? root.thresholds
                    root.updated = s.updated
                    root.mutedUntil = s.muted_until ?? 0
                    if (root.current >= root.clusters.length) root.current = 0
                } catch (e) { root.clusters = [] }
            } else if (source.includes("#refresh")) {
                // systemctl start returns when the check has finished, so the results are ready now.
                root.checking = false
                root.load()
            } else if (source.includes("#mute")) {
                root.load()
            }
        }
    }
    function load() { exec.connectSource(loadCmd) }
    // Starts the shared check job; if the timer's run is already going, systemd waits for that one instead.
    property bool checking: false
    function refresh() {
        if (checking) return
        checking = true
        exec.connectSource("systemctl --user start kube-health.service; true #refresh" + Date.now())
    }
    function mute(arg) { exec.connectSource(bin + " --mute " + arg + " #mute" + Date.now()) }
    Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.load() }

    Plasmoid.icon: "kube-health"
    toolTipMainText: "Kube Health"
    toolTipSubText: clusters.map(c => `${c.name}: ${c.up ? pct(c) : "DOWN"}`).join("\n")
        + (pipelines.length ? `\nPipelines: ${pipesFailed} failed, ${pipesRunning} running` : "")
        + (mutedUntil ? "\n🔕 " + muteText() : "")

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

    // Indented, clickable run or PR/MR row under an expanded repo.
    component SubRow: MouseArea {
        property string status
        property string url
        property string text
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.gridUnit * 2
        implicitHeight: subLabel.implicitHeight
        enabled: !!url
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: Qt.openUrlExternally(url)
        RowLayout {
            anchors.left: parent.left; anchors.right: parent.right
            Dot { color: root.pipeColor(status) }
            PlasmaComponents.Label { id: subLabel; Layout.fillWidth: true; elide: Text.ElideRight; text: parent.parent.text }
        }
    }

    // One usage line: "CPU  [=====     ]  1.9 / 3.8 cores  49%"
    component Usage: RowLayout {
        property string label
        property var value       // percent or null
        property string detail
        property int max
        PlasmaComponents.Label { text: label; Layout.preferredWidth: Kirigami.Units.gridUnit * 2; opacity: 0.7 }
        PlasmaComponents.ProgressBar {
            Layout.fillWidth: true
            from: 0; to: 100
            value: parent.value ?? 0
            visible: parent.value !== null && parent.value !== undefined
        }
        PlasmaComponents.Label {
            text: parent.value === null || parent.value === undefined ? "no metrics" : detail + "  " + parent.value + "%"
            color: (parent.value ?? 0) >= max ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            horizontalAlignment: Text.AlignRight
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 38
        Layout.preferredHeight: Kirigami.Units.gridUnit * 34
        readonly property var c: root.clusters[root.current] || null
        readonly property var nodes: c ? (c.nodes.list ?? [])
            .filter(n => !root.problemsOnly || root.nodeState(n) !== "ok")
            .slice().sort((a, b) => ((root.nodeState(a) === "ok") - (root.nodeState(b) === "ok"))
                || (Math.max(b.cpu_pct ?? 0, b.mem_pct ?? 0) - Math.max(a.cpu_pct ?? 0, a.mem_pct ?? 0))) : []
        readonly property var pods: c ? root.byNs(c.pods.recent)
            .filter(p => !root.problemsOnly || p.state === "bad" || p.state === "pending") : []
        readonly property var alerts: c ? root.byNs(c.alerts)
            .filter(a => !root.sevFilter || a.severity === root.sevFilter) : []
        readonly property var events: c ? root.byNs(c.events) : []

        // ---- Header: view switch + actions ----
        RowLayout {
            PlasmaComponents.TabBar {
                Layout.fillWidth: true
                visible: root.clusters.length > 0 && root.pipelines.length > 0
                currentIndex: root.showPipelines ? 1 : 0
                PlasmaComponents.TabButton {
                    text: "Clusters" + (root.clusters.some(x => root.bad(x)) ? "  🔴" : "")
                    onClicked: root.view = "clusters"
                }
                PlasmaComponents.TabButton {
                    text: "Pipelines" + (root.pipesFailed ? "  🔴 " + root.pipesFailed : "")
                        + (root.pipesRunning ? "  🔵 " + root.pipesRunning : "")
                    onClicked: root.view = "pipelines"
                }
            }
            Kirigami.Heading {
                Layout.fillWidth: true
                visible: !(root.clusters.length > 0 && root.pipelines.length > 0)
                level: 4
                text: root.showPipelines ? "Pipelines" : "Clusters"
            }
            PlasmaComponents.ToolButton {
                visible: !root.checking
                icon.name: "view-refresh"
                PlasmaComponents.ToolTip { text: "Check now" }
                onClicked: root.refresh()
            }
            PlasmaComponents.BusyIndicator {
                visible: root.checking
                running: root.checking
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                PlasmaComponents.ToolTip.text: "Checking…"
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

        // ---- Pipelines view ----
        PlasmaComponents.ScrollView {
            id: pipeScroll
            visible: root.showPipelines
            Layout.fillWidth: true
            Layout.fillHeight: true
            PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
            ColumnLayout {
                width: pipeScroll.availableWidth
                spacing: Kirigami.Units.largeSpacing
                Repeater {
                    model: root.showPipelines ? root.pipelines : []
                    ColumnLayout {
                        id: repoBlock
                        required property var modelData
                        readonly property var p: modelData
                        readonly property bool open: !!root.expanded[p.id]
                        readonly property bool hasMore: (p.history?.length ?? 0) > 1 || (p.mrs?.length ?? 0) > 0
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        // Header: click to expand, link button opens the latest run.
                        RowLayout {
                            Layout.fillWidth: true
                            MouseArea {
                                Layout.fillWidth: true
                                implicitHeight: head.implicitHeight
                                cursorShape: repoBlock.hasMore ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (repoBlock.hasMore) root.toggleExpanded(repoBlock.p.id)
                                RowLayout {
                                    id: head
                                    anchors.left: parent.left; anchors.right: parent.right
                                    Kirigami.Icon {
                                        source: repoBlock.open ? "arrow-down" : "arrow-right"
                                        opacity: repoBlock.hasMore ? 0.7 : 0
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    }
                                    Dot { color: root.pipeColor(repoBlock.p.status) }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        PlasmaComponents.Label {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            text: "<b>" + repoBlock.p.name + "</b>  " + repoBlock.p.branch + "  ·  "
                                                + root.pipeText(repoBlock.p.status)
                                                + (repoBlock.p.status !== "failed" && repoBlock.p.last_finished === "failed" ? " (last run failed)" : "")
                                                + (repoBlock.p.age ? "  ·  " + repoBlock.p.age : "")
                                                + ((repoBlock.p.mrs?.length ?? 0) ? "  ·  " + repoBlock.p.mrs.length
                                                    + (repoBlock.p.id.startsWith("gitlab:") ? " MRs" : " PRs") : "")
                                        }
                                        PlasmaComponents.Label {
                                            visible: !!repoBlock.p.sha
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            opacity: 0.7
                                            text: (repoBlock.p.sha || "") + "  " + (repoBlock.p.title || "")
                                        }
                                    }
                                }
                            }
                            PlasmaComponents.ToolButton {
                                visible: !!repoBlock.p.url
                                icon.name: "internet-web-browser"
                                PlasmaComponents.ToolTip { text: "Open latest run" }
                                onClicked: Qt.openUrlExternally(repoBlock.p.url)
                            }
                        }

                        // Expanded: recent runs, then open PRs/MRs.
                        PlasmaComponents.Label {
                            visible: repoBlock.open && (repoBlock.p.history?.length ?? 0) > 1
                            Layout.leftMargin: Kirigami.Units.gridUnit * 2
                            text: "Recent runs"; opacity: 0.6; font: Kirigami.Theme.smallFont
                        }
                        Repeater {
                            model: repoBlock.open ? (repoBlock.p.history ?? []).slice(1) : []
                            SubRow {
                                status: modelData.status; url: modelData.url
                                text: modelData.sha + "  " + modelData.title + "  ·  " + modelData.age
                            }
                        }
                        PlasmaComponents.Label {
                            visible: repoBlock.open && (repoBlock.p.mrs?.length ?? 0) > 0
                            Layout.leftMargin: Kirigami.Units.gridUnit * 2
                            text: repoBlock.p.id.startsWith("gitlab:") ? "Open merge requests" : "Open pull requests"
                            opacity: 0.6; font: Kirigami.Theme.smallFont
                        }
                        Repeater {
                            model: repoBlock.open ? (repoBlock.p.mrs ?? []) : []
                            SubRow {
                                status: modelData.status; url: modelData.url
                                text: modelData.ref + "  " + modelData.title + "  ·  " + modelData.branch
                                    + (modelData.author ? "  ·  " + modelData.author : "") + "  ·  " + modelData.age
                            }
                        }
                    }
                }
            }
        }

        // ---- Clusters view ----
        RowLayout {
            visible: !root.showPipelines && !!c
            PlasmaComponents.ComboBox {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                model: root.clusters.map(x => (root.bad(x) ? "🔴 " : "") + x.name)
                currentIndex: root.current
                onActivated: { root.current = currentIndex; root.nsFilter = "" }
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true; wrapMode: Text.Wrap
                text: !c ? "" : (c.up ? "API ✅" : "API 🔴 unreachable")
                    + "   Watchdog " + (c.watchdog === null ? "n/a" : c.watchdog ? "✅" : "🔴 missing")
                    + "   Pods " + root.pct(c)
                    + (c.nodes ? "   Nodes " + (c.nodes.total - c.nodes.notready.length) + "/" + c.nodes.total : "")
                color: c ? root.color(c) : Kirigami.Theme.textColor
            }
        }

        RowLayout {
            visible: !root.showPipelines && !!c
            PlasmaComponents.TabBar {
                Layout.fillWidth: true
                currentIndex: root.section
                PlasmaComponents.TabButton { text: "Nodes (" + nodes.length + ")"; onClicked: root.section = 0 }
                PlasmaComponents.TabButton { text: "Pods (" + pods.length + ")"; onClicked: root.section = 1 }
                PlasmaComponents.TabButton { text: "Alerts (" + alerts.length + ")"; onClicked: root.section = 2 }
                PlasmaComponents.TabButton { text: "Warnings (" + events.length + ")"; onClicked: root.section = 3 }
            }
            PlasmaComponents.ComboBox {
                visible: root.section > 0
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                model: ["All namespaces"].concat(c ? c.pods.namespaces : [])
                onActivated: root.nsFilter = currentIndex === 0 ? "" : currentText
            }
        }

        RowLayout {
            visible: !root.showPipelines && !!c && root.section !== 3
            PlasmaComponents.CheckBox {
                visible: root.section <= 1
                text: "Problems only"
                checked: root.problemsOnly
                onToggled: root.problemsOnly = checked
            }
            PlasmaComponents.ComboBox {
                visible: root.section === 2
                readonly property var values: ["", "critical", "warning", "info"]
                model: ["All severities", "Critical", "Warning", "Info"]
                currentIndex: values.indexOf(root.sevFilter)
                onActivated: root.sevFilter = values[currentIndex]
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                opacity: 0.6
                text: "Updated " + root.updated.replace("T", " ").replace("Z", " UTC")
            }
        }

        PlasmaComponents.ScrollView {
            id: scroll
            visible: !root.showPipelines
            Layout.fillWidth: true
            Layout.fillHeight: true
            PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
            ColumnLayout {
                width: scroll.availableWidth

                PlasmaComponents.Label {
                    text: "Nothing here"; opacity: 0.6
                    visible: [nodes, pods, alerts, events][root.section].length === 0
                }
                Repeater {
                    model: root.section === 0 ? nodes : []
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        Dot { color: root.stateColor(root.nodeState(modelData)) }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            PlasmaComponents.Label {
                                Layout.fillWidth: true; elide: Text.ElideRight
                                text: "<b>" + modelData.name + "</b>"
                                    + (modelData.pool ? "  ·  " + modelData.pool : "")
                                    + "  ·  " + modelData.pods + "/" + modelData.pods_max + " pods"
                                    + "  ·  " + modelData.age
                                    + (modelData.ready ? "" : "  ·  🔴 NotReady")
                                    + (modelData.pressure.length ? "  ·  🟠 " + modelData.pressure.join(", ") : "")
                            }
                            Usage {
                                Layout.fillWidth: true
                                label: "CPU"; value: modelData.cpu_pct; max: root.thresholds.node_cpu
                                detail: (modelData.cpu_used ?? 0).toFixed(1) + " / " + modelData.cpu_total.toFixed(1) + " cores"
                            }
                            Usage {
                                Layout.fillWidth: true
                                label: "RAM"; value: modelData.mem_pct; max: root.thresholds.node_mem
                                detail: root.gib(modelData.mem_used ?? 0) + " / " + root.gib(modelData.mem_total) + " GiB"
                            }
                        }
                    }
                }
                Repeater {
                    model: root.section === 1 ? pods.slice(0, 50) : []
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
                    model: root.section === 2 ? alerts : []
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
                    model: root.section === 3 ? events : []
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
