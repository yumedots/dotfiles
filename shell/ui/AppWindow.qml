import QtQuick
import Quickshell
import qs

FloatingWindow {
	id: root

	default property alias content: body.data

	signal appClosed()

	property string appTitle: ""
	property int appMinWidth: 640
	property int appMinHeight: 400

	title: root.appTitle
	minimumSize: Qt.size(root.appMinWidth, root.appMinHeight)
	color: Config.surface
	visible: true
	implicitWidth: 1280
	implicitHeight: 800

	onClosed: {
		root.appClosed();
	}

	Connections {
		target: Quickshell

		function onLastWindowClosed() {
			Qt.quit();
		}
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
