import QtQuick
import Quickshell
import qs

FloatingWindow {
	id: root

	default property alias content: body.data

	signal closed()

	property string appTitle: ""
	property int appMinWidth: 640
	property int appMinHeight: 400

	title: root.appTitle
	color: Config.surface
	visible: true
	width: 1280
	height: 800

	onVisibleChanged: {
		if (visible) return;
		root.closed();
		Qt.quit();
	}

	Shortcut {
		sequence: "F11"
		onActivated: root.fullscreen = !root.fullscreen
	}

	Item {
		id: body

		anchors.fill: parent
		focus: true
	}
}
