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
// The topbar widget opens a small panel; this is the same panel on its own,
// filling the screen. The keybind switches between the two.
PanelWindow {
	id: root

	property bool shown: false
	property bool alwaysMapped: true
	property string target: ""

	anchors.top: true
	anchors.left: true
	anchors.bottom: true
	anchors.right: true

	implicitWidth: root.screen ? root.screen.width : 1
	implicitHeight: root.screen ? root.screen.height : 1

	exclusiveZone: -1
	color: "transparent"

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "agentwindow"
	WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
	WlrLayershell.focusable: true

	// The window is always mapped, the way the launcher is, so it can be shown
	// without waiting for a surface. When it is hidden it lets the clicks
	// through.
	visible: root.alwaysMapped || root.shown || card.opacity > 0

	Region {
		id: emptyRegion

		width: 0
		height: 0
	}

	mask: root.shown ? null : emptyRegion

	// Clicking the background closes the window.
	MouseArea {
		anchors.fill: parent
		onClicked: root.shown = false
	}

	// The card is the panel itself, so it fades with the window.
	Item {
		id: card

		anchors.centerIn: parent
		width: winCard.width
		height: winCard.height

		opacity: root.shown ? 1 : 0

		Behavior on opacity {
			NumberAnimation {
				duration: Config.popupFadeMs
				easing.type: Easing.InOutCubic
			}
		}

		Rectangle {
			anchors.fill: parent
			radius: 8
			color: Config.surfaceTranslucent
			border.width: 1
			border.color: Config.dim
		}

		Item {
			id: winCard

			width: panel.implicitWidth
			height: panel.implicitHeight

			AgentPanel {
				id: panel

				x: 0
				y: 0

				source: null
				injectedTarget: root.target

				onCloseRequested: root.shown = false
			}
		}
	}
}

