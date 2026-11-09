import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services

PanelWindow {
	anchors {
		left: true
		bottom: true
	}

	margins {
		left: 16
		bottom: 16
	}

	implicitWidth: badge.width + 16
	implicitHeight: badge.height + 8
	color: "transparent"
	exclusionMode: ExclusionMode.Ignore

	Rectangle {
		id: badge

		anchors.centerIn: parent
		width: label.width + 16
		height: label.height + 8
		radius: 4
		color: Config.surfaceTranslucent
		border.width: 1
		border.color: Config.dim

		Text {
			id: label

			anchors.centerIn: parent
			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: Config.muted
			text: Yudae.agentName || "yudae"
		}
	}
}
