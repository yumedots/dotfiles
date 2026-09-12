import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Row {
	id: root
	spacing: 10

	Repeater {
		model: SystemTray.items

		delegate: Item {
			required property var modelData

			implicitWidth: 14
			implicitHeight: 14

			IconImage {
				anchors.fill: parent
				source: modelData.icon
				implicitSize: 14
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
