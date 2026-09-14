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
	property bool wantsKeyboard: false

	property real anchorX: 0
	property bool shown: false

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
	margins.left: Math.round(border.gapsOut + Math.max(0, Math.min(root.wantedX + Config.tooltipOffsetX, root.limitX)))

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
	}

	function close() {
		root.shown = false;
		root.visible = false;
	}

	function hideNow() {
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
		padding: border.gapsIn
		borderColors: root.borderColors
		borderWidth: root.borderWidth
		borderOpacity: 1
	}
}
