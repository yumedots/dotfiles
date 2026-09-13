import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "config.js" as Config
import "helpers.js" as Helpers

Item {
	id: root

	default property alias content: body.data

	property var borderColors: null
	property real borderWidth: -1
	property real padding: 0
	property real borderOpacity: 1
	property var hyprBorder: ({ colors: null, angle: 0, width: null })
	property var hyprGaps: ({ inner: null, outer: null })
	property var hyprAnimation: ({ windowsIn: null })

	readonly property var themeColors: root.borderColors !== null
		? root.borderColors
		: (root.hyprBorder.colors !== null ? root.hyprBorder.colors : [Config.borderFallbackColor])
	readonly property real themeWidth: root.borderWidth >= 0
		? root.borderWidth
		: (root.hyprBorder.width !== null ? root.hyprBorder.width : Config.borderFallbackWidth)
	readonly property real themeAngle: root.hyprBorder.angle
	readonly property real inset: root.themeWidth + root.padding
	readonly property real gapsIn: root.hyprGaps.inner !== null ? root.hyprGaps.inner : Config.gapsInFallback
	readonly property real gapsOut: root.hyprGaps.outer !== null ? root.hyprGaps.outer : Config.gapsOutFallback
	readonly property real appearDuration: root.hyprAnimation.windowsIn !== null ? root.hyprAnimation.windowsIn : Config.popupFallbackDuration

	readonly property alias contentWidth: body.childrenRect.width
	readonly property alias contentHeight: body.childrenRect.height

	Component.onCompleted: {
		hyprOptions.reload();
		hyprAnimation.reload();
	}

	Connections {
		target: Hyprland

		function onRawEvent(event) {
			if (event.name === "configreloaded") {
				hyprOptions.reload();
				hyprAnimation.reload();
			}
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

	Process {
		id: hyprAnimation

		command: ["hyprctl", "-j", "animations"]

		function reload() {
			if (!hyprAnimation.running)
				hyprAnimation.running = true;
		}

		stdout: StdioCollector {
			onStreamFinished: root.hyprAnimation = { windowsIn: Helpers.parseHyprAnimationSpeed(text, "windowsIn") }
		}
	}

	Item {
		id: frame

		anchors.fill: parent
		clip: true

		Rectangle {
			id: gradient

			opacity: root.borderOpacity
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
			anchors.margins: root.inset
		}
	}
}
