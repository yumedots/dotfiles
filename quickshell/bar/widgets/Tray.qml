import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.ui
import qs

Row {
	id: root
	spacing: 10

	readonly property real baselineLift: Math.ceil(Config.barThickness)

	Repeater {
		model: SystemTray.items

		delegate: Item {
			required property var modelData

			implicitWidth: Config.trayIconSize
			implicitHeight: Config.trayIconSize

			AppIcon {
				anchors.fill: parent
				source: modelData.icon
				implicitSize: Config.trayIconSize
			}
		}
	}
}
