import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

PanelWindow {
	id: root

	default property alias content: border.content

	property Item anchorItem
	property var anchorWindow
	property var borderColors: null
	property real borderWidth: -1
	property bool pinned: false
	property bool wantsKeyboard: false
	property bool alignRight: false
	property real contentPadding: -1

	property real anchorX: 0
	property bool shown: false
	property bool warmed: false
	property bool revealed: false

	readonly property bool atBottom: root.anchorWindow !== null && root.anchorWindow.atBottom === true
	readonly property real wantedX: root.anchorX + (root.anchorItem ? root.anchorItem.width : 0) / 2 - root.cardWidth / 2
	readonly property real limitX: (root.anchorWindow ? root.anchorWindow.width : 0) - root.cardWidth
	readonly property real hang: Math.round(border.gapsOut + Config.tooltipOffsetY)

	screen: root.anchorWindow ? root.anchorWindow.screen : null

	readonly property bool modal: root.wantsKeyboard
	readonly property real scale: border.scale
	readonly property real cardWidth: Helpers.snap(border.contentWidth + 2 * border.inset, root.scale)
	readonly property real cardHeight: Helpers.snap(border.contentHeight + 2 * border.inset, root.scale)
	readonly property real cardX: Helpers.snap(root.alignRight
		? (root.screen ? root.screen.width : root.cardWidth) - root.cardWidth - border.gapsOut
		: border.gapsOut + Helpers.clamp(root.wantedX + Config.tooltipOffsetX, 0, root.limitX), root.scale)
	readonly property real cardY: Helpers.snap(root.atBottom
		? (root.screen ? root.screen.height : root.cardHeight) - root.hang - root.cardHeight
		: root.hang, root.scale)

	anchors {
		top: root.modal || !root.atBottom
		bottom: root.modal || root.atBottom
		left: true
		right: root.modal
	}

	margins.top: root.modal || root.atBottom ? 0 : root.hang
	margins.bottom: root.modal || !root.atBottom ? 0 : root.hang
	margins.left: root.modal ? 0 : root.cardX

	implicitWidth: root.cardWidth
	implicitHeight: root.cardHeight

	exclusiveZone: 0
	color: "transparent"
	visible: false

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "tooltip"
	WlrLayershell.keyboardFocus: root.wantsKeyboard && root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

	function refreshAnchor() {
		if (root.anchorItem === null || root.anchorWindow === null)
			return;

		root.anchorX = root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0).x;
	}

	function open() {
		root.refreshAnchor();
		root.shown = true;
		root.visible = true;

		if (root.warmed)
			root.revealed = true;
		else {
			warmup.sampled = -1;
			warmup.restart();
		}
	}

	Timer {
		id: warmup

		interval: 30
		repeat: true
		property real sampled: -1

		onTriggered: {
			if (root.cardHeight !== warmup.sampled) {
				warmup.sampled = root.cardHeight;
				return;
			}

			warmup.stop();
			warmup.sampled = -1;
			root.warmed = true;

			if (root.shown)
				root.revealed = true;
		}
	}

	function close() {
		root.revealed = false;
		root.shown = false;
		root.visible = false;
	}

	function hideNow() {
		root.revealed = false;
		root.shown = false;
		root.visible = false;
	}

	function toggle() {
		if (root.shown)
			root.close();
		else
			root.open();
	}

	onVisibleChanged: {
		if (!root.visible)
			root.shown = false;
	}

	MouseArea {
		id: backdrop

		anchors.fill: parent
		acceptedButtons: Qt.AllButtons

		onPressed: function (mouse) {
			if (root.modal && card.contains(card.mapFromItem(backdrop, mouse.x, mouse.y)))
				return;

			root.close();
		}
	}

	Item {
		id: card

		x: root.modal ? root.cardX : 0
		y: root.modal ? root.cardY : 0
		width: root.cardWidth
		height: root.cardHeight

		HyprBorder {
			id: border

			anchors.fill: parent
			padding: root.contentPadding >= 0 ? root.contentPadding : border.gapsIn
			borderColors: root.borderColors
			borderWidth: root.borderWidth
			borderOpacity: 1
			visible: root.revealed

			Keys.onPressed: function (event) {
				if (!Input.cancel(event))
					return;

				root.close();
				event.accepted = true;
			}
		}
	}
}
