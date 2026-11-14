import QtQuick
import qs

Item {
	id: root

	property bool checked: false

	signal toggled()

	implicitWidth: 20
	implicitHeight: 20

	Rectangle {
		anchors.fill: parent
		radius: width / 2
		color: root.checked ? Config.foreground : Qt.lighter(Config.launcherHighlight, 1.7)

		Behavior on color {
			ColorAnimation { duration: 110 }
		}
	}

	Rectangle {
		anchors.centerIn: parent
		width: root.checked ? 8 : 0
		height: width
		radius: width / 2
		color: Config.surface

		Behavior on width {
			NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
		}
	}

	MouseArea {
		anchors.fill: parent
		anchors.margins: -4
		onClicked: root.toggled()
	}
}
