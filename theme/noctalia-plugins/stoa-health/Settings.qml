// Stoa Health — Settings UI
// Rendered inside Noctalia Settings (gear in the plugin manager, or
// "Settings" in the bar widget's right-click menu).
//
// Two sections:
//   1. Appearance  — bar icon, badge, pulse, poll, terminal
//   2. Actions     — per-action editor (icon, label, visibility, order)
//                    grouped by tab.

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    spacing: Style.marginM

    property var pluginApi: null

    // ── Appearance values ──
    property string valueIcon:        pluginApi?.pluginSettings?.icon ?? "heart"
    property string valueTerminal:    pluginApi?.pluginSettings?.terminal ?? "kitty"
    property int    valuePollSeconds: pluginApi?.pluginSettings?.pollSeconds ?? 30
    property bool   valueShowBadge:   pluginApi?.pluginSettings?.showBadge ?? true
    property bool   valuePulse:       pluginApi?.pluginSettings?.pulse ?? true

    // ── Action list (deep copy so we can edit before save) ──
    readonly property var _defaultActions: [
        { "id": "doctor",     "tab": "vitals", "label": "Run Doctor",                "icon": "refresh",   "visible": true },
        { "id": "log",        "tab": "vitals", "label": "Log",                       "icon": "file-text", "visible": true },
        { "id": "journal",    "tab": "vitals", "label": "Journal",                   "icon": "terminal",  "visible": true },
        { "id": "pkgsnap",    "tab": "snap",   "label": "Snapshot packages now",     "icon": "save",      "visible": true },
        { "id": "backup",     "tab": "snap",   "label": "Backup configs now",        "icon": "save",      "visible": true },
        { "id": "lspkg",      "tab": "snap",   "label": "Browse snapshots",          "icon": "folder",    "visible": true },
        { "id": "lsbk",       "tab": "snap",   "label": "Browse backups",            "icon": "folder",    "visible": true },
        { "id": "updAll",     "tab": "maint",  "label": "Update all (pacman + AUR)", "icon": "download",  "visible": true },
        { "id": "updSys",     "tab": "maint",  "label": "Update system (pacman)",    "icon": "download",  "visible": true },
        { "id": "updAur",     "tab": "maint",  "label": "Update AUR (yay)",          "icon": "download",  "visible": true },
        { "id": "cleanDry",   "tab": "maint",  "label": "Cleanup (dry run)",         "icon": "trash",     "visible": true },
        { "id": "cleanApply", "tab": "maint",  "label": "Cleanup (apply)",           "icon": "trash",     "visible": true },
        { "id": "sched",      "tab": "maint",  "label": "Toggle boot schedule",      "icon": "clock",     "visible": true },
        { "id": "fw",         "tab": "maint",  "label": "Firewall (locksmith)",      "icon": "shield",    "visible": true }
    ]
    property var valueActions: []

    // Icon options reused everywhere
    readonly property var _iconChoices: [
        { "key": "refresh",        "name": "Refresh" },
        { "key": "file-text",      "name": "File / Log" },
        { "key": "terminal",       "name": "Terminal" },
        { "key": "save",           "name": "Save" },
        { "key": "folder",         "name": "Folder" },
        { "key": "download",       "name": "Download" },
        { "key": "trash",          "name": "Trash" },
        { "key": "clock",          "name": "Clock" },
        { "key": "shield",         "name": "Shield" },
        { "key": "stethoscope",    "name": "Stethoscope" },
        { "key": "activity",       "name": "Activity" },
        { "key": "heart",          "name": "Heart" },
        { "key": "heartbeat",      "name": "Heartbeat" },
        { "key": "first-aid-kit",  "name": "First-aid kit" },
        { "key": "alert-triangle", "name": "Alert" },
        { "key": "cpu",            "name": "CPU" },
        { "key": "database",       "name": "Database" },
        { "key": "device-tv",      "name": "Display" },
        { "key": "tool",           "name": "Tool" },
        { "key": "settings",       "name": "Settings" },
    ]

    Component.onCompleted: {
        // Initial copy: prefer saved actions, fall back to defaults.
        var src = pluginApi?.pluginSettings?.actions ?? _defaultActions
        valueActions = JSON.parse(JSON.stringify(src))
    }

    function _refresh() {
        // Force the Repeaters to re-bind after an in-place edit.
        var v = valueActions
        valueActions = []
        valueActions = v
    }
    function _indexOfId(id) {
        for (var i = 0; i < valueActions.length; i++)
            if (valueActions[i].id === id) return i
        return -1
    }
    function setLabel(id, txt)    { var i = _indexOfId(id); if (i < 0) return; valueActions[i].label = txt; _refresh() }
    function setIcon(id, ic)      { var i = _indexOfId(id); if (i < 0) return; valueActions[i].icon = ic;    _refresh() }
    function setVisible(id, vis)  { var i = _indexOfId(id); if (i < 0) return; valueActions[i].visible = vis;_refresh() }
    function moveUp(id) {
        var i = _indexOfId(id); if (i < 0) return
        // Find previous index in the same tab
        for (var j = i - 1; j >= 0; j--) {
            if (valueActions[j].tab === valueActions[i].tab) {
                var tmp = valueActions[i]; valueActions[i] = valueActions[j]; valueActions[j] = tmp
                _refresh(); return
            }
        }
    }
    function moveDown(id) {
        var i = _indexOfId(id); if (i < 0) return
        for (var j = i + 1; j < valueActions.length; j++) {
            if (valueActions[j].tab === valueActions[i].tab) {
                var tmp = valueActions[i]; valueActions[i] = valueActions[j]; valueActions[j] = tmp
                _refresh(); return
            }
        }
    }
    function resetActions() {
        valueActions = JSON.parse(JSON.stringify(_defaultActions))
    }

    function _actionsForTab(t) {
        var out = []
        for (var i = 0; i < valueActions.length; i++)
            if (valueActions[i].tab === t) out.push(valueActions[i])
        return out
    }

    function saveSettings() {
        if (!pluginApi) return
        pluginApi.pluginSettings.icon        = root.valueIcon
        pluginApi.pluginSettings.terminal    = root.valueTerminal
        pluginApi.pluginSettings.pollSeconds = root.valuePollSeconds
        pluginApi.pluginSettings.showBadge   = root.valueShowBadge
        pluginApi.pluginSettings.pulse       = root.valuePulse
        pluginApi.pluginSettings.actions     = root.valueActions
        pluginApi.saveSettings()
    }

    // ══════════════════════════════════════════════════════════════
    //   APPEARANCE
    // ══════════════════════════════════════════════════════════════
    NLabel { text: "Appearance"; font.weight: Font.Bold }

    NComboBox {
        Layout.fillWidth: true
        label: "Bar icon"
        description: "Icon shown in the bar capsule"
        model: root._iconChoices
        currentKey: root.valueIcon
        onSelected: key => root.valueIcon = key
    }

    NToggle {
        Layout.fillWidth: true
        label: "Issue count badge"
        description: "Show a red counter on the icon when issues or failed units exist"
        checked: root.valueShowBadge
        onToggled: checked => root.valueShowBadge = checked
    }

    NToggle {
        Layout.fillWidth: true
        label: "Pulse on warning/error"
        description: "Animate the icon when the system needs attention"
        checked: root.valuePulse
        onToggled: checked => root.valuePulse = checked
    }

    NSpinBox {
        Layout.fillWidth: true
        label: "Poll interval (seconds)"
        description: "How often the bar widget re-reads system status"
        from: 5
        to: 300
        stepSize: 5
        value: root.valuePollSeconds
        onValueChanged: root.valuePollSeconds = value
    }

    NTextInput {
        Layout.fillWidth: true
        label: "Terminal"
        description: "Terminal emulator used to run actions (must support --title and --hold)"
        text: root.valueTerminal
        onTextChanged: root.valueTerminal = text
    }

    // ══════════════════════════════════════════════════════════════
    //   ACTIONS
    // ══════════════════════════════════════════════════════════════
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        Layout.topMargin: Style.marginM

        NLabel {
            Layout.fillWidth: true
            text: "Actions"
            font.weight: Font.Bold
        }
        Item {
            implicitWidth: resetText.implicitWidth + Style.marginS * 2
            implicitHeight: 24
            Rectangle {
                anchors.fill: parent; radius: Style.radiusS
                color: resetHover.containsMouse ? Color.mErrorContainer : Color.mSurfaceVariant
            }
            NText {
                id: resetText
                anchors.centerIn: parent
                text: "Reset to defaults"
                font.pointSize: Style.fontSizeXS
                color: Color.mOnSurface
            }
            MouseArea {
                id: resetHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.resetActions()
            }
        }
    }

    NLabel {
        Layout.fillWidth: true
        text: "Edit label, icon, visibility and order for each action. Use ↑/↓ to move within a tab."
        font.pointSize: Style.fontSizeXS
        wrapMode: Text.WordWrap
    }

    // Section header + repeater for each tab
    Repeater {
        model: [
            { key: "vitals", label: "Vitals tab" },
            { key: "snap",   label: "Snapshots tab" },
            { key: "maint",  label: "Maintenance tab" },
        ]

        delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.marginXS
            Layout.topMargin: Style.marginS

            NLabel {
                Layout.fillWidth: true
                text: modelData.label
                font.pointSize: Style.fontSizeS
                font.weight: Font.Bold
                color: Color.mOnSurfaceVariant
            }

            Repeater {
                model: root._actionsForTab(modelData.key)
                delegate: Item {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.radiusS
                        color: Color.mSurfaceVariant
                        opacity: modelData.visible === false ? 0.3 : 0.5
                    }

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: Style.marginS
                            rightMargin: Style.marginS
                            topMargin: 4; bottomMargin: 4
                        }
                        spacing: Style.marginXS

                        // ↑ button
                        Item {
                            implicitWidth: 22; implicitHeight: 22
                            Rectangle {
                                anchors.fill: parent; radius: Style.radiusS
                                color: upHover.containsMouse ? Color.mPrimaryContainer : "transparent"
                            }
                            NIcon {
                                anchors.centerIn: parent
                                icon: "chevron-up"
                                pointSize: Style.fontSizeS
                                color: Color.mOnSurface
                            }
                            MouseArea {
                                id: upHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.moveUp(modelData.id)
                            }
                        }
                        // ↓ button
                        Item {
                            implicitWidth: 22; implicitHeight: 22
                            Rectangle {
                                anchors.fill: parent; radius: Style.radiusS
                                color: downHover.containsMouse ? Color.mPrimaryContainer : "transparent"
                            }
                            NIcon {
                                anchors.centerIn: parent
                                icon: "chevron-down"
                                pointSize: Style.fontSizeS
                                color: Color.mOnSurface
                            }
                            MouseArea {
                                id: downHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.moveDown(modelData.id)
                            }
                        }

                        // Preview icon
                        NIcon {
                            icon: modelData.icon
                            pointSize: Style.fontSizeS
                            color: Color.mOnSurfaceVariant
                        }

                        // Label editor
                        NTextInput {
                            Layout.fillWidth: true
                            text: modelData.label
                            onTextChanged: root.setLabel(modelData.id, text)
                        }

                        // Icon picker — compact
                        NComboBox {
                            Layout.preferredWidth: 110
                            model: root._iconChoices
                            currentKey: modelData.icon
                            onSelected: key => root.setIcon(modelData.id, key)
                        }

                        // Visibility toggle
                        NToggle {
                            checked: modelData.visible !== false
                            onToggled: checked => root.setVisible(modelData.id, checked)
                        }
                    }
                }
            }
        }
    }
}
