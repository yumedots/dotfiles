import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.services
import qs.ui
import "../tooltips"

// The agent as a window.
//
// The topbar widget opens a small panel; this is the same panel on its own, in
// a real window that the compositor manages, so it can be moved, resized,
// raised and closed like any other window.
FloatingWindow {
	id: root

	property bool shown: false
	property string target: ""

	title: "Agent"
	visible: root.shown

	// The width of the panel, which is the width of the content plus the
	// padding around it.
	readonly property real panelWidth: Config.agentPanelWidth + 2 * Config.agentPanelPadding

	// The height of the bar along the top, which drags the window around.
	readonly property real titleHeight: 28

	// The window is made at the size of its content, because the compositor
	// keeps the size a window is made with.
	implicitWidth: root.panelWidth
	implicitHeight: 620

	minimumSize: Qt.size(320, 420)
	maximumSize: Qt.size(1200, 2000)

	color: Config.surfaceTranslucent

	// The panel fills the window, so it grows and shrinks with it.
	AgentPanel {
		id: agentPanel

		anchors.fill: parent
		anchors.topMargin: root.titleHeight

		source: null
		injectedTarget: root.target

		onCloseRequested: root.shown = false;
	}

	// A bar along the top, which drags the window around.
	Item {
		id: titleBar

		anchors.top: parent.top
		anchors.left: parent.left
		anchors.right: parent.right
		height: root.titleHeight

		Rectangle {
			anchors.fill: parent
			color: Config.surfaceTranslucent
		}

		Text {
			anchors.left: parent.left
			anchors.leftMargin: Config.agentPanelPadding
			anchors.verticalCenter: parent.verticalCenter

			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: Config.muted
			text: root.title
		}

		MouseArea {
			anchors.fill: parent

			onPressed: function (mouse) {
				root.startSystemMove();
			}
		}
	}

	// A grip on the edge of the window, to resize it by dragging.
	MouseArea {
		id: east

		anchors.right: parent.right
		anchors.top: parent.top
		anchors.bottom: parent.bottom
		width: 6

		cursorShape: Qt.SizeHorCursor

		onPressed: function (mouse) {
			root.startSystemResize(Qt.RightEdge);
		}
	}

	MouseArea {
		id: south

		anchors.bottom: parent.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		height: 6

		cursorShape: Qt.SizeVerCursor

		onPressed: function (mouse) {
			root.startSystemResize(Qt.BottomEdge);
		}
	}

	// A grip in the corner, to resize it in both directions at once.
	MouseArea {
		id: corner

		anchors.right: parent.right
		anchors.bottom: parent.bottom
		width: 14
		height: 14

		cursorShape: Qt.SizeBDiagCursor

		onPressed: function (mouse) {
			root.startSystemResize(Qt.RightEdge | Qt.BottomEdge);
		}
	}
}
