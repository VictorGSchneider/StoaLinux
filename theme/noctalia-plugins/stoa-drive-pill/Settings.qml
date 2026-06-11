// Stoa Drive Pill — Settings UI

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    spacing: Style.marginM

    property var pluginApi: null

    property string valueIcon:        pluginApi?.pluginSettings?.icon ?? "cloud-upload"
    property string valueFileManager: pluginApi?.pluginSettings?.fileManager ?? "thunar"
    property int    valuePollSeconds: pluginApi?.pluginSettings?.pollSeconds ?? 5
    property bool   valueShowBadge:   pluginApi?.pluginSettings?.showBadge ?? true

    function saveSettings() {
        if (!pluginApi) return
        pluginApi.pluginSettings.icon        = root.valueIcon
        pluginApi.pluginSettings.fileManager = root.valueFileManager
        pluginApi.pluginSettings.pollSeconds = root.valuePollSeconds
        pluginApi.pluginSettings.showBadge   = root.valueShowBadge
        pluginApi.saveSettings()
    }

    NComboBox {
        Layout.fillWidth: true
        label: "Bar icon"
        description: "Icon shown when at least one drive is mounted (cloud-off is always used when none are)"
        model: [
            { "key": "cloud-upload",   "name": "Cloud upload" },
            { "key": "cloud-download", "name": "Cloud download" },
            { "key": "cloud",          "name": "Cloud" },
            { "key": "database",       "name": "Database" },
            { "key": "folder",         "name": "Folder" },
            { "key": "server",         "name": "Server" },
        ]
        currentKey: root.valueIcon
        onSelected: key => root.valueIcon = key
    }

    NToggle {
        Layout.fillWidth: true
        label: "Mounted/total badge"
        description: "Show a m/t counter next to the icon when not all drives are mounted"
        checked: root.valueShowBadge
        onToggled: checked => root.valueShowBadge = checked
    }

    NSpinBox {
        Layout.fillWidth: true
        label: "Poll interval (seconds)"
        description: "How often the widget re-reads drive status"
        from: 2
        to: 120
        stepSize: 1
        value: root.valuePollSeconds
        onValueChanged: root.valuePollSeconds = value
    }

    NTextInput {
        Layout.fillWidth: true
        label: "File manager"
        description: "Used by the Open ~/Drive action"
        text: root.valueFileManager
        onTextChanged: root.valueFileManager = text
    }
}
