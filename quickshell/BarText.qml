import QtQuick
import "theme.js" as Theme

Item {
	id: root

	property string text: ""
	property color color: Theme.foreground
	property int pixelSize: Theme.fontSize
	property real padding: 0

	readonly property var ink: metrics.tightBoundingRect

	implicitWidth: label.implicitWidth + root.padding * 2
	implicitHeight: ink.height

	TextMetrics {
		id: metrics
		font.family: Theme.fontFamily
		font.pixelSize: root.pixelSize
		text: root.text
	}

	Text {
		id: label

		x: root.padding
		y: metrics.boundingRect.y - metrics.tightBoundingRect.y

		font.family: Theme.fontFamily
		font.pixelSize: root.pixelSize
		color: root.color
		text: root.text
	}
}
