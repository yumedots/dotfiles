import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.ui

PanelWindow {
	id: root

	required property var modelData
	property bool shown: false
	property string name: "none"

	signal dismissed()

	screen: root.modelData

	anchors.top: true
	anchors.left: true
	anchors.bottom: true
	anchors.right: true

	implicitWidth: root.screen ? root.screen.width : 1
	implicitHeight: root.screen ? root.screen.height : 1

	exclusiveZone: -1
	color: "transparent"
	visible: root.shown

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "saver"
	WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
	WlrLayershell.focusable: true

	onShownChanged: if (root.shown) Qt.callLater(surface.forceActiveFocus)

	Item {
		id: surface

		anchors.fill: parent
		focus: true
		clip: true

		Rectangle {
			anchors.fill: parent
			color: Config.saverGround
		}

		ScreenSaver {
			anchors.fill: parent
			name: root.name
			strength: 1
			running: root.shown
		}

		MouseArea {
			anchors.fill: parent
			onClicked: root.dismissed()
		}

		Keys.onPressed: function (event) {
			root.dismissed();
			event.accepted = true;
		}
	}
}
