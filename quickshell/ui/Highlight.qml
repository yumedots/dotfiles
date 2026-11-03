import QtQuick
import qs

Rectangle {
	id: root

	property bool active: true
	property bool fillParent: true
	property real radius: 0

	readonly property color ink: root.active ? Config.launcherHighlightText : Config.foreground

	anchors.fill: root.fillParent ? parent : undefined
	color: root.active ? Config.launcherHighlight : "transparent"
}
