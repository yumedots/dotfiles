import QtQuick
import qs

Item {
	id: root

	property string text: ""
	property color color: Config.foreground
	property int pixelSize: Config.fontSize
	property real padding: 0

	readonly property var sampleInk: metrics.tightBoundingRect

	implicitWidth: label.implicitWidth + root.padding * 2
	implicitHeight: root.sampleInk.height

	TextMetrics {
		id: metrics
		font.family: Config.fontFamily
		font.pixelSize: root.pixelSize
		text: Config.valueSample
	}

	Text {
		id: label

		x: root.padding
		y: metrics.boundingRect.y - metrics.tightBoundingRect.y

		font.family: Config.fontFamily
		font.pixelSize: root.pixelSize
		color: root.color
		text: root.text
	}
}
