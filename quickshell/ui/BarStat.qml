import QtQuick
import QtQuick.Window
import qs

Item {
	id: root

	property real pct: 0
	property string mode: Config.barStatMode
	property bool mono: Config.barStatMono
	property bool dim: false
	property color dimColor: Config.dim
	property color barColor: Config.red
	property color textColor: root.barColor
	property string icon: ""
	property string value: ""
	property real gap: 0
	property bool showBar: true
	property bool sweep: false
	property real sweepWidth: 0
	property var bar: null
	property bool popupKeyboard: true
	property bool popupPinned: false
	property bool popupAlignRight: false
	property real popupPadding: -1
	property alias popupContent: popupWindow.content

	readonly property alias popupVisible: popupWindow.shown

	function openPopup() {
		popupWindow.open();
	}

	function closePopup() {
		popupWindow.hideNow();
	}

	function isPopupOpen() {
		return popupWindow.shown;
	}

	readonly property bool iconMode: root.mode === "icon"
	readonly property color inkColor: root.dim ? root.dimColor : (root.mono ? Config.foreground : root.textColor)
	readonly property int filled: Helpers.filledCells(root.pct, Config.barCells)
	readonly property real valueAscent: -valueMetrics.boundingRect.y
	readonly property real iconAscent: -iconMetrics.boundingRect.y
	readonly property real valueBelow: valueMetrics.tightBoundingRect.y + valueMetrics.tightBoundingRect.height
	readonly property real inkAbove: Math.max(-iconsMetrics.tightBoundingRect.y, -valueMetrics.tightBoundingRect.y)
	readonly property real inkBelow: Math.max(iconsMetrics.tightBoundingRect.y + iconsMetrics.tightBoundingRect.height, root.valueBelow)
	readonly property real textOffset: root.implicitHeight - root.inkAbove - root.valueBelow
	readonly property real baselineLift: 0

	implicitWidth: root.iconMode ? Math.ceil(iconMetrics.width + root.gap) : Config.lineLength + root.gap
	readonly property real contentHeight: Math.round(root.inkAbove + root.inkBelow)
	implicitHeight: root.contentHeight + (root.showBar ? Math.ceil(Config.barThickness) : 0)

	Tooltip {
		id: popupWindow

		anchorWindow: root.bar
		anchorItem: root
		contentPadding: root.popupPadding
		wantsKeyboard: root.popupKeyboard
		pinned: root.popupPinned
		alignRight: root.popupAlignRight
	}

	TextMetrics {
		id: iconsMetrics
		font.family: Config.fontFamily
		font.pixelSize: Config.iconSize
		text: Config.iconCpu + Config.iconMemory + Config.iconVolumeLow + Config.iconVolumeMid + Config.iconVolumeHigh
	}

	TextMetrics {
		id: iconMetrics
		font.family: Config.fontFamily
		font.pixelSize: Config.iconSize
		text: root.icon
	}

	TextMetrics {
		id: valueMetrics
		font.family: Config.fontFamily
		font.pixelSize: Config.fontSize
		text: Config.valueSample
	}

	Item {
		id: content

		anchors.left: parent.left
		anchors.top: parent.top
		anchors.bottom: parent.bottom
		width: Config.lineLength

		Text {
			id: labelIcon

			x: 0
			y: root.inkAbove - root.iconAscent
			font.family: Config.fontFamily
			font.pixelSize: Config.iconSize
			color: root.inkColor
			text: root.icon
		}

		Text {
			id: labelValue

			visible: !root.iconMode
			x: labelIcon.width
			y: root.inkAbove - root.valueAscent
			width: Math.max(labelValue.implicitWidth, content.width - labelIcon.width)
			horizontalAlignment: Text.AlignHCenter
			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: root.inkColor
			text: root.value
		}

		Item {
			id: line

			visible: root.showBar && !root.iconMode
			anchors.left: parent.left
			anchors.bottom: parent.bottom
			width: parent.width
			height: Config.barThickness
			clip: true

			Rectangle {
				anchors.fill: parent
				color: Config.dim
			}

			Rectangle {
				id: fill

				visible: !root.sweep
				anchors.left: parent.left
				anchors.top: parent.top
				anchors.bottom: parent.bottom
				width: line.width * root.filled / Config.barCells
				color: root.barColor
			}

			Item {
				id: sweepLine

				visible: root.sweep && root.filled > 0
				anchors.top: parent.top
				anchors.bottom: parent.bottom
				width: root.sweepWidth > 0 ? Math.min(root.sweepWidth, line.width) : line.width

				readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
				readonly property int steps: Math.max(1, Config.sweepSteps)
				readonly property int deviceWidth: Math.max(sweepLine.steps, Math.round(width * sweepLine.dpr))
				readonly property int fadePixels: Math.round(sweepLine.deviceWidth * Config.sweepFade)

				property real travel: -sweepLine.deviceWidth

				function edge(step) {
					return Math.round(step * sweepLine.fadePixels / sweepLine.steps);
				}

				function toLocal(pixels) {
					return pixels / sweepLine.dpr;
				}

				x: sweepLine.toLocal(Math.round(sweepLine.travel))

				Repeater {
					model: sweepLine.steps

					delegate: Rectangle {
						required property int index

						x: sweepLine.toLocal(sweepLine.edge(index))
						width: sweepLine.toLocal(sweepLine.edge(index + 1) - sweepLine.edge(index))
						anchors.top: parent.top
						anchors.bottom: parent.bottom
						color: root.barColor
						opacity: (index + 1) / (sweepLine.steps + 1)
					}
				}

				Rectangle {
					anchors.top: parent.top
					anchors.bottom: parent.bottom
					x: sweepLine.toLocal(sweepLine.fadePixels)
					width: sweepLine.toLocal(sweepLine.deviceWidth - sweepLine.fadePixels)
					color: root.barColor
				}

				NumberAnimation on travel {
					from: -sweepLine.deviceWidth
					to: Math.round(line.width * sweepLine.dpr)
					duration: Config.barSweepMs
					loops: Animation.Infinite
				}
			}
		}
	}
}
