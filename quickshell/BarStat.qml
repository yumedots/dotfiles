import QtQuick
import "theme.js" as Theme

Item {
	id: root

	property real pct: 0
	property color barColor: Theme.red
	property color textColor: root.barColor
	property string icon: ""
	property string value: ""
	property real gap: 0

	readonly property int filled: Theme.filledCells(root.pct)
	readonly property real valueAscent: -valueMetrics.boundingRect.y
	readonly property real iconAscent: -iconMetrics.boundingRect.y
	readonly property real valueBelow: valueMetrics.tightBoundingRect.y + valueMetrics.tightBoundingRect.height
	readonly property real inkAbove: Math.max(-iconsMetrics.tightBoundingRect.y, -valueMetrics.tightBoundingRect.y)
	readonly property real inkBelow: Math.max(iconsMetrics.tightBoundingRect.y + iconsMetrics.tightBoundingRect.height, root.valueBelow)
	readonly property real textOffset: root.implicitHeight - root.inkAbove - root.valueBelow

	implicitWidth: Theme.lineLength + root.gap
	readonly property real contentHeight: Math.round(root.inkAbove + root.inkBelow)
	implicitHeight: root.contentHeight + Math.ceil(Theme.barThickness)

	TextMetrics {
		id: iconsMetrics
		font.family: Theme.fontFamily
		font.pixelSize: Theme.iconSize
		text: Theme.iconCpu + Theme.iconMemory + Theme.iconVolumeLow + Theme.iconVolumeMid + Theme.iconVolumeHigh
	}

	TextMetrics {
		id: iconMetrics
		font.family: Theme.fontFamily
		font.pixelSize: Theme.iconSize
		text: root.icon
	}

	TextMetrics {
		id: valueMetrics
		font.family: Theme.fontFamily
		font.pixelSize: Theme.fontSize
		text: Theme.valueSample
	}

	Item {
		id: content

		anchors.left: parent.left
		anchors.top: parent.top
		anchors.bottom: parent.bottom

		width: Theme.lineLength

		Text {
			id: labelIcon

			x: 0
			y: root.inkAbove - root.iconAscent

			font.family: Theme.fontFamily
			font.pixelSize: Theme.iconSize
			color: root.textColor
			text: root.icon
		}

		Text {
			id: labelValue

			x: labelIcon.width
			y: root.inkAbove - root.valueAscent

			width: Math.max(labelValue.implicitWidth, content.width - labelIcon.width)
			horizontalAlignment: Text.AlignHCenter

			font.family: Theme.fontFamily
			font.pixelSize: Theme.fontSize
			color: root.textColor
			text: root.value
		}

		Item {
			id: line

			anchors.left: parent.left
			anchors.bottom: parent.bottom

			width: parent.width
			height: Theme.barThickness

			Rectangle {
				id: fill

				anchors.left: parent.left
				anchors.top: parent.top
				anchors.bottom: parent.bottom
				width: line.width * root.filled / Theme.barCells
				color: root.barColor
			}

			Rectangle {
				anchors.left: fill.right
				anchors.right: parent.right
				anchors.top: parent.top
				anchors.bottom: parent.bottom
				color: Theme.dim
			}
		}
	}
}
