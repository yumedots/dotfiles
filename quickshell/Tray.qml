import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "theme.js" as Theme

Row {
	id: root
	spacing: 10

	Repeater {
		model: SystemTray.items

		delegate: Item {
			required property var modelData

			implicitWidth: Theme.trayIconSize
			implicitHeight: Theme.trayIconSize

			IconImage {
				anchors.fill: parent
				source: modelData.icon
				implicitSize: Theme.trayIconSize
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
