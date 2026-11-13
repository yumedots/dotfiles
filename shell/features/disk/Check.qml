import QtQuick
import qs
import qs.ui

Item {
	id: root

	property bool checked: false

	signal toggled()

	implicitWidth: 18
	implicitHeight: 18

	Rectangle {
		anchors.fill: parent
		color: root.checked ? Config.foreground : Config.launcherSearchBox
		border.color: Config.dim
		border.width: 1
	}

	Glyph {
		anchors.centerIn: parent
		visible: root.checked
		glyph: Config.launcherIconActive
		size: 10
		color: Config.surface
	}

	MouseArea {
		anchors.fill: parent
		onClicked: root.toggled()
	}
}
