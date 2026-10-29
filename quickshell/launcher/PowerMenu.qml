import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.ui

PanelWindow {
	id: root

	property bool shown: false
	property bool active: true
	property bool alwaysMapped: false
	property int index: 0

	readonly property var actions: Config.powerActions
	readonly property int count: root.actions.length

	anchors.top: true
	anchors.left: true
	anchors.bottom: true
	anchors.right: true

	implicitWidth: root.screen ? root.screen.width : 1
	implicitHeight: root.screen ? root.screen.height : 1

	exclusiveZone: -1
	color: "transparent"

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "powermenu"
	WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
	WlrLayershell.focusable: true

	visible: root.alwaysMapped || root.shown || card.opacity > 0

	Region {
		id: emptyRegion

		width: 0
		height: 0
	}

	mask: root.shown ? null : emptyRegion

	function open() {
		root.index = 0;
		root.shown = true;
		Qt.callLater(function () { card.forceActiveFocus(); });
	}

	function close() {
		root.shown = false;
	}

	function execute() {
		Yudae.cmd("launcher", { power: root.index });
		root.close();
	}

	function step(delta) {
		if (root.count > 0)
			root.index = (root.index + delta + root.count) % root.count;
	}

	Rectangle {
		id: scrim

		anchors.fill: parent
		color: Config.surface
		opacity: root.shown ? Config.wallpaperScrim : 0

		Behavior on opacity {
			NumberAnimation {
				duration: Config.wallpaperScrimMs
				easing.type: Easing.OutCubic
			}
		}
	}

	MouseArea {
		id: backdrop

		anchors.fill: parent
		enabled: root.shown

		onClicked: function (mouse) {
			if (!card.contains(card.mapFromItem(backdrop, mouse.x, mouse.y)))
				root.close();
		}
	}

	HyprBorder {
		id: card

		anchors.centerIn: parent
		width: menu.implicitWidth + card.inset * 2
		height: menu.implicitHeight + card.inset * 2
		padding: Config.launcherPadding
		backgroundColor: Config.surfaceTranslucent
		opacity: root.shown ? 1 : 0
		visible: root.shown || card.opacity > 0
		focus: true

		Behavior on opacity {
			NumberAnimation {
				duration: Config.popupFadeMs
				easing.type: Easing.OutCubic
			}
		}

		Keys.onPressed: function (event) {
			if (event.key === Qt.Key_Escape)
				root.close();
			else if (event.key === Qt.Key_Left)
				root.step(-1);
			else if (event.key === Qt.Key_Right)
				root.step(1);
			else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
				root.execute();
		}

		IconRow {
			id: menu

			width: parent.width
			height: parent.height
			columns: Math.max(1, root.count)
			cell: Config.powerCellSize
			iconSize: Config.powerIconSize
			highlightSize: Config.powerHighlightSize
			labelSize: Config.powerLabelSize
			model: root.actions
			index: root.index
		}

		MouseArea {
			anchors.fill: parent
			hoverEnabled: true

			onPositionChanged: function (mouse) { root.index = Calc.clamp(Math.floor(mouse.x / Config.powerCellSize), 0, Math.max(0, root.count - 1)); }
			onClicked: root.execute()
		}
	}
}
