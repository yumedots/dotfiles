import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs

Item {
	id: root

	default property alias content: body.data

	property var borderColors: null
	property real borderWidth: -1
	property color backgroundColor: Config.surfaceTranslucent
	property real padding: 0
	property real borderOpacity: 1
	property var hyprBorder: ({ colors: null, angle: 0, width: null })
	property var hyprGaps: ({ inner: null, outer: null })

	readonly property var themeColors: root.borderColors !== null
		? root.borderColors
		: (root.hyprBorder.colors !== null ? root.hyprBorder.colors : [Config.borderFallbackColor])
	readonly property real scale: Hyprland.focusedMonitor && Hyprland.focusedMonitor.scale > 0 ? Hyprland.focusedMonitor.scale : 1
	readonly property real wantedWidth: root.borderWidth >= 0
		? root.borderWidth
		: (root.hyprBorder.width !== null ? root.hyprBorder.width : Config.borderFallbackWidth)
	readonly property real themeWidth: Helpers.snap(root.wantedWidth, root.scale)
	readonly property real themeAngle: root.hyprBorder.angle
	readonly property var edges: Helpers.gradientEdges(root.themeColors, root.themeAngle, frame.width, frame.height, root.themeWidth)
	readonly property real inset: root.themeWidth + root.padding
	readonly property real gapsIn: root.hyprGaps.inner !== null ? root.hyprGaps.inner : Config.gapsInFallback
	readonly property real gapsOut: root.hyprGaps.outer !== null ? root.hyprGaps.outer : Config.gapsOutFallback

	readonly property alias contentWidth: body.childrenRect.width
	readonly property alias contentHeight: body.childrenRect.height

	Component.onCompleted: {
		hyprOptions.reload();
	}

	Connections {
		target: Hyprland

		function onRawEvent(event) {
			if (event.name === "configreloaded")
				hyprOptions.reload();
		}
	}

	Process {
		id: hyprOptions

		command: ["sh", "-c", "hyprctl getoption -j general:col.active_border; hyprctl getoption -j general:border_size; hyprctl getoption -j general:gaps_in; hyprctl getoption -j general:gaps_out"]

		function reload() {
			if (!hyprOptions.running)
				hyprOptions.running = true;
		}

		stdout: StdioCollector {
			onStreamFinished: {
				root.hyprBorder = Helpers.parseHyprBorder(text);
				root.hyprGaps = Helpers.parseHyprGaps(text);
			}
		}
	}

	Item {
		id: frame

		anchors.fill: parent
		clip: true

		Rectangle {
			anchors.fill: parent
			anchors.margins: root.themeWidth
			color: root.backgroundColor
		}

		Repeater {
			model: root.edges

			delegate: Rectangle {
				required property var modelData

				x: modelData.x
				y: modelData.y
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
