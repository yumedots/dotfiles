import QtQuick
import Quickshell.Hyprland
import qs
import qs.services

Item {
	id: root

	default property alias content: body.data

	property var borderColors: null
	property real borderWidth: -1
	property color backgroundColor: Config.surfaceTranslucent
	property real padding: 0
	property real borderOpacity: 1
	property bool shadowEnabled: true
	property real shadowTopReach: -1
	property real shadowBottomReach: -1
	property real stripWidth: 1
	property color stripColor: "#ff000000"

	readonly property var hyprBorder: Yudae.screenBorder.colors ? Yudae.screenBorder : ({ colors: [], angle: 0, width: null })
	readonly property var themeColors: root.borderColors !== null
		? root.borderColors
		: (root.hyprBorder.colors.length > 0 ? root.hyprBorder.colors : [Config.borderFallbackColor])
	readonly property real scale: Hyprland.focusedMonitor && Hyprland.focusedMonitor.scale > 0 ? Hyprland.focusedMonitor.scale : 1
	readonly property real wantedWidth: root.borderWidth >= 0 ? root.borderWidth : (root.hyprBorder.width == null ? Config.borderFallbackWidth : root.hyprBorder.width)
	readonly property real themeWidth: Math.round(root.wantedWidth * root.scale) / root.scale
	readonly property real themeAngle: root.hyprBorder.angle || 0
	readonly property real strip: root.stripWidth > 0 ? Math.round(root.stripWidth * root.scale) / root.scale : 0
	readonly property var edges: root.edgeRects(root.themeColors, root.themeAngle, frame.width - root.strip * 2, frame.height - root.strip * 2, root.themeWidth)
	readonly property real inset: root.strip + root.themeWidth + root.padding

	readonly property alias contentWidth: body.childrenRect.width
	readonly property alias contentHeight: body.childrenRect.height

	function edgeRects(colors, angle, width, height, thickness) {
		const span = Math.max(width, height) * 1.5;
		const radians = angle * Math.PI / 180;
		const cos = Math.cos(radians);
		const sin = Math.sin(radians);
		const first = Qt.color(colors[0]);
		const last = Qt.color(colors.length > 1 ? colors[colors.length - 1] : colors[0]);
		const blend = (from, to, k) => Math.round((from + (to - from) * k) * 255) / 255;
		const at = (x, y) => ((x - width / 2) * cos + (y - height / 2) * sin + span / 2) / span;
		const sample = (x, y) => colors.length < 2 ? first : Qt.rgba(blend(first.r, last.r, at(x, y)), blend(first.g, last.g, at(x, y)), blend(first.b, last.b, at(x, y)), blend(first.a, last.a, at(x, y)));

		return ["top", "bottom", "left", "right"].map((edge) => {
			const long = edge === "top" || edge === "bottom";

			return {
				x: edge === "right" ? width - thickness : 0,
				y: edge === "bottom" ? height - thickness : (long ? 0 : thickness),
				width: long ? width : thickness,
				height: long ? thickness : Math.max(0, height - thickness * 2),
				horizontal: long,
				start: sample(edge === "right" ? width : 0, edge === "bottom" ? height : 0),
				end: sample(edge === "left" ? 0 : width, edge === "top" ? 0 : height)
			};
		});
	}

	HyprShadow {
		z: -1
		anchors.fill: parent
		shadowEnabled: root.shadowEnabled
		topReach: root.shadowTopReach
		bottomReach: root.shadowBottomReach
	}

	Item {
		id: frame

		anchors.fill: parent
		clip: true

		Rectangle {
			anchors.fill: parent
			color: root.stripColor
			visible: root.strip > 0
		}

		Rectangle {
			anchors.fill: parent
			anchors.margins: root.strip + root.themeWidth
			color: root.backgroundColor
		}

		Repeater {
			model: root.edges

			delegate: Rectangle {
				required property var modelData

				x: modelData.x + root.strip
				y: modelData.y + root.strip
				width: modelData.width
				height: modelData.height
				visible: modelData.width > 0 && modelData.height > 0
				opacity: root.borderOpacity

				gradient: Gradient {
					orientation: modelData.horizontal ? Gradient.Horizontal : Gradient.Vertical

					GradientStop { position: 0; color: modelData.start }
					GradientStop { position: 1; color: modelData.end }
				}
			}
		}

		Item {
			id: body

			anchors.fill: parent
			anchors.margins: root.inset
		}
	}
}
