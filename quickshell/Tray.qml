import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "config.js" as Config

Row {
	id: root
	spacing: 10

	Repeater {
		model: SystemTray.items

		delegate: Item {
			required property var modelData

			implicitWidth: Config.trayIconSize
			implicitHeight: Config.trayIconSize

			IconImage {
				anchors.fill: parent
				source: modelData.icon
				implicitSize: Config.trayIconSize
			}

			MouseArea {
				anchors.fill: parent
				acceptedButtons: Qt.LeftButton | Qt.MiddleButton
				onClicked: function (mouse) {
					if (mouse.button === Qt.LeftButton)
						modelData.activate();
					else
						modelData.secondaryActivate();
				}
			}
		}
	}
}
