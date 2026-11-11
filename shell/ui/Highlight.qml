import QtQuick
import qs

Rectangle {
	id: root

	property bool active: true
	property bool fillParent: true

	readonly property color ink: root.active ? Config.launcherHighlightText : Config.foreground

	anchors.fill: root.fillParent ? parent : undefined
	radius: Config.mixerRowRadius
	color: Config.launcherHighlight
	opacity: root.active ? 1 : 0

	Behavior on opacity {
		NumberAnimation {
			duration: Math.round(Config.toggleMs / 2)
			easing.type: Easing.OutCubic
		}
	}
}
