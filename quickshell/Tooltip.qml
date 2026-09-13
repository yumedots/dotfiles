import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "config.js" as Config
import "helpers.js" as Helpers

PopupWindow {
	id: root

	default property alias content: body.data

	property Item anchorItem
	property var anchorWindow
	property real padding: Config.tooltipPadding
	property real gap: Config.tooltipGap
	property int closeDelay: Config.tooltipCloseDelay
	property real borderWidth: -1
	property var borderColors: null
	property bool anchorHovered: false
	property var hyprBorder: ({ colors: null, angle: 0, width: null })

	readonly property var themeColors: root.borderColors !== null
		? root.borderColors
		: (root.hyprBorder.colors !== null ? root.hyprBorder.colors : [Config.tooltipBorderColor])
	readonly property real themeWidth: root.borderWidth >= 0
		? root.borderWidth
		: (root.hyprBorder.width !== null ? root.hyprBorder.width : Config.tooltipBorderWidth)
	readonly property real themeAngle: root.hyprBorder.angle

	property real anchorX: 0
	property real anchorY: 0

	readonly property real wantedX: root.anchorX + (root.anchorItem ? root.anchorItem.width : 0) / 2 - root.implicitWidth / 2
	readonly property real limitX: (root.anchorWindow ? root.anchorWindow.width : 0) - root.implicitWidth

	anchor.window: root.anchorWindow
	anchor.rect.x: Math.round(Math.max(0, Math.min(root.wantedX, root.limitX)))
	anchor.rect.y: Math.round(root.anchorY + (root.anchorItem ? root.anchorItem.height : 0) + root.gap)

	function refreshAnchor() {
		if (root.anchorItem === null || root.anchorWindow === null)
			return;

		const point = root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0);

		root.anchorX = point.x;
		root.anchorY = point.y;
	}

	implicitWidth: body.childrenRect.width + 2 * (root.themeWidth + root.padding)
	implicitHeight: body.childrenRect.height + 2 * (root.themeWidth + root.padding)

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

	Component.onCompleted: hyprOptions.reload()

	Connections {
		target: Hyprland

		function onRawEvent(event) {
			if (event.name === "configreloaded")
				hyprOptions.reload();
		}
	}

	Process {
		id: hyprOptions

		command: ["sh", "-c", "hyprctl getoption -j general:col.active_border; hyprctl getoption -j general:border_size"]

		function reload() {
			if (!hyprOptions.running)
				hyprOptions.running = true;
		}

		stdout: StdioCollector {
			onStreamFinished: root.hyprBorder = Helpers.parseHyprBorder(text)
		}
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

	Item {
		id: frame

		anchors.fill: parent
		clip: true

		Rectangle {
			id: gradient

			width: Math.max(frame.width, frame.height) * 1.5
			height: width
			anchors.centerIn: parent
			rotation: root.themeAngle

			gradient: Gradient {
				orientation: Gradient.Horizontal

				GradientStop { position: 0; color: root.themeColors[0] }
				GradientStop { position: 1; color: root.themeColors[root.themeColors.length - 1] }
			}
		}

		Rectangle {
			anchors.fill: parent
			anchors.margins: root.themeWidth
			color: Config.background
		}

		Item {
			id: body

			anchors.fill: parent
			anchors.margins: root.themeWidth + root.padding
		}
	}
}
