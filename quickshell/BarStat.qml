import QtQuick
import "config.js" as Config
import "helpers.js" as Helpers

Item {
	id: root

	signal clicked()
	signal exited()

	property real pct: 0
	property color barColor: Config.red
	property color textColor: root.barColor
	property string icon: ""
	property string value: ""
	property real gap: 0

	readonly property int filled: Helpers.filledCells(root.pct, Config.barCells)
	readonly property real valueAscent: -valueMetrics.boundingRect.y
	readonly property real iconAscent: -iconMetrics.boundingRect.y
	readonly property real valueBelow: valueMetrics.tightBoundingRect.y + valueMetrics.tightBoundingRect.height
	readonly property real inkAbove: Math.max(-iconsMetrics.tightBoundingRect.y, -valueMetrics.tightBoundingRect.y)
	readonly property real inkBelow: Math.max(iconsMetrics.tightBoundingRect.y + iconsMetrics.tightBoundingRect.height, root.valueBelow)
	readonly property real textOffset: root.implicitHeight - root.inkAbove - root.valueBelow

	implicitWidth: Config.lineLength + root.gap
	readonly property real contentHeight: Math.round(root.inkAbove + root.inkBelow)
	implicitHeight: root.contentHeight + Math.ceil(Config.barThickness)

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
			color: root.textColor
			text: root.icon
		}

		Text {
			id: labelValue

			x: labelIcon.width
			y: root.inkAbove - root.valueAscent

			width: Math.max(labelValue.implicitWidth, content.width - labelIcon.width)
			horizontalAlignment: Text.AlignHCenter

			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: root.textColor
			text: root.value
		}

		Item {
			id: line

			anchors.left: parent.left
			anchors.bottom: parent.bottom

			width: parent.width
			height: Config.barThickness

			Rectangle {
				id: fill

				anchors.left: parent.left
				anchors.top: parent.top
				anchors.bottom: parent.bottom
				width: line.width * root.filled / Config.barCells
				color: root.barColor
			}

			Rectangle {
				anchors.left: fill.right
				anchors.right: parent.right
				anchors.top: parent.top
				anchors.bottom: parent.bottom
				color: Config.dim
			}
		}
	}

	readonly property alias hovered: area.containsMouse

	MouseArea {
		id: area

		anchors.fill: parent
		hoverEnabled: true

		onClicked: root.clicked()
		onExited: root.exited()
	}
}
