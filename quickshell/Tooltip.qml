import QtQuick
import Quickshell
import "config.js" as Config

PopupWindow {
	id: root

	default property alias content: border.content

	property Item anchorItem
	property var anchorWindow
	property real padding: Config.tooltipPadding
	property real gap: Config.tooltipGap
	property int closeDelay: Config.tooltipCloseDelay
	property var borderColors: null
	property real borderWidth: -1
	property bool anchorHovered: false

	property real anchorX: 0

	readonly property real wantedX: root.anchorX + (root.anchorItem ? root.anchorItem.width : 0) / 2 - root.implicitWidth / 2
	readonly property real limitX: (root.anchorWindow ? root.anchorWindow.width : 0) - root.implicitWidth

	anchor.window: root.anchorWindow
	anchor.rect.x: Math.round(Math.max(0, Math.min(root.wantedX + Config.tooltipOffsetX, root.limitX)))
	anchor.rect.y: root.anchorWindow ? root.anchorWindow.height + border.gapsOut + Config.tooltipOffsetY : 0

	function refreshAnchor() {
		if (root.anchorItem === null || root.anchorWindow === null)
			return;

		root.anchorX = root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0).x;
	}

	implicitWidth: border.contentWidth + 2 * border.inset
	implicitHeight: border.contentHeight + 2 * border.inset

	color: "transparent"
	visible: false

	function open() {
		closeTimer.stop();
		root.visible = true;
	}

	function close() {
		closeTimer.stop();
		root.visible = false;
	}

	function toggle() {
		if (root.visible)
			root.close();
		else
			root.open();
	}

	function scheduleClose() {
		if (root.visible)
			closeTimer.restart();
	}

	onVisibleChanged: {
		if (root.visible)
			root.refreshAnchor();
		else
			closeTimer.stop();
	}

	HoverHandler {
		id: selfHover
	}

	Timer {
		id: closeTimer

		interval: root.closeDelay

		onTriggered: {
			if (!selfHover.hovered && !root.anchorHovered)
				root.visible = false;
		}
	}

	HyprBorder {
		id: border

		anchors.fill: parent
		padding: root.padding
		borderColors: root.borderColors
		borderWidth: root.borderWidth
	}
}
