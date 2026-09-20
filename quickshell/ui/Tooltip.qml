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
	readonly property real wantedX: root.anchorX + (root.anchorItem ? root.anchorItem.width : 0) / 2 - root.implicitWidth / 2
	readonly property real limitX: (root.anchorWindow ? root.anchorWindow.width : 0) - root.implicitWidth
	readonly property real hang: Math.round(border.gapsOut + Config.tooltipOffsetY)

	screen: root.anchorWindow ? root.anchorWindow.screen : null

	anchors {
		top: !root.atBottom
		bottom: root.atBottom
		left: true
	}

	margins.top: root.atBottom ? 0 : root.hang
	margins.bottom: root.atBottom ? root.hang : 0
	margins.left: root.alignRight
		? Math.round((root.screen ? root.screen.width : root.implicitWidth) - root.implicitWidth - border.gapsOut)
		: Math.round(border.gapsOut + Math.max(0, Math.min(root.wantedX + Config.tooltipOffsetX, root.limitX)))

	implicitWidth: border.contentWidth + 2 * border.inset
	implicitHeight: border.contentHeight + 2 * border.inset

	exclusiveZone: 0
	color: "transparent"
	visible: false

	WlrLayershell.layer: WlrLayer.Top
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
			if (root.implicitHeight !== warmup.sampled) {
				warmup.sampled = root.implicitHeight;
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

	HyprBorder {
		id: border

		anchors.fill: parent
		padding: root.contentPadding >= 0 ? root.contentPadding : border.gapsIn
		borderColors: root.borderColors
		borderWidth: root.borderWidth
		borderOpacity: 1
		visible: root.revealed

		Keys.onPressed: function (event) {
			if (event.key !== Qt.Key_Escape)
				return;

			root.close();
			event.accepted = true;
		}
	}
}
