import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services

PanelWindow {
	anchors {
		right: true
		bottom: true
	}

	margins {
		right: 16
		bottom: 16
	}

	implicitWidth: 120
	implicitHeight: 36
	color: "transparent"
	exclusionMode: ExclusionMode.Ignore

	Rectangle {
		anchors.fill: parent
		radius: 4
		color: Config.surfaceTranslucent
		border.width: 1
		border.color: Config.foreground

		Text {
			anchors.centerIn: parent
			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: Config.foreground
			text: "plugin"
		}
	}
}
