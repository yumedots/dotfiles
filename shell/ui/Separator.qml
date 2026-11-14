import QtQuick
import qs

Rectangle {
	id: root

	readonly property real scale: root.Window.window ? root.Window.window.devicePixelRatio : 1

	implicitHeight: 1 / root.scale
	height: root.implicitHeight
	color: Config.dim
}
