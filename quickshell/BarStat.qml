import QtQuick
import "theme.js" as Theme

Item {
	id: root

	property real pct: 0
	property color barColor: Theme.red
	property color textColor: root.barColor
	property string icon: ""
	property string value: ""

	readonly property int filled: Theme.filledCells(root.pct)

	implicitWidth: Theme.lineLength
	implicitHeight: Theme.barHeight

	Text {
		id: label

		anchors.left: parent.left
		anchors.verticalCenter: parent.verticalCenter

		font.family: Theme.fontFamily
		font.pixelSize: Theme.fontSize
		color: root.textColor
		text: root.icon + "  " + root.value
	}

	Item {
		id: line

		anchors.left: parent.left
		anchors.bottom: parent.bottom

		width: root.implicitWidth
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
