// Stoa Health — Settings UI
// Rendered inside Noctalia Settings (gear button in the plugin manager,
// or "Settings" in the bar widget's right-click menu).
//
// Local value* properties buffer edits; the framework calls
// saveSettings() when the user hits Save, so Cancel discards cleanly.

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    spacing: Style.marginM

    property var pluginApi: null

    property string valueIcon:        pluginApi?.pluginSettings?.icon ?? "heart"
    property string valueTerminal:    pluginApi?.pluginSettings?.terminal ?? "kitty"
    property int    valuePollSeconds: pluginApi?.pluginSettings?.pollSeconds ?? 30
    property bool   valueShowBadge:   pluginApi?.pluginSettings?.showBadge ?? true
    property bool   valuePulse:       pluginApi?.pluginSettings?.pulse ?? true

    function saveSettings() {
        if (!pluginApi) return
        pluginApi.pluginSettings.icon        = root.valueIcon
        pluginApi.pluginSettings.terminal    = root.valueTerminal
        pluginApi.pluginSettings.pollSeconds = root.valuePollSeconds
        pluginApi.pluginSettings.showBadge   = root.valueShowBadge
        pluginApi.pluginSettings.pulse       = root.valuePulse
        pluginApi.saveSettings()
    }

    NComboBox {
        Layout.fillWidth: true
        label: "Bar icon"
        description: "Icon shown in the bar capsule"
        model: [
            { "key": "heart",       "name": "Heart" },
            { "key": "activity",    "name": "Activity" },
            { "key": "stethoscope", "name": "Stethoscope" },
            { "key": "heartbeat",   "name": "Heartbeat" },
            { "key": "shield",      "name": "Shield" },
            { "key": "first-aid-kit", "name": "First-aid kit" },
        ]
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
}
