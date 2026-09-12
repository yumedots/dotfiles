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

	implicitWidth: Math.max(label.implicitWidth, bar.implicitWidth)
	implicitHeight: Theme.barHeight

	Text {
		id: label

		anchors.horizontalCenter: parent.horizontalCenter
		anchors.verticalCenter: parent.verticalCenter

		font.family: Theme.fontFamily
		font.pixelSize: Theme.fontSize
		color: root.textColor
		text: root.icon + "  " + root.value
	}

	Item {
		id: bar

		anchors.horizontalCenter: parent.horizontalCenter
		anchors.bottom: parent.bottom

		implicitWidth: Theme.barCells * Theme.barCellWidth
		implicitHeight: Theme.barThickness
		width: implicitWidth
		height: implicitHeight

		Rectangle {
			anchors.left: parent.left
			anchors.top: parent.top
			anchors.bottom: parent.bottom
			width: root.filled * Theme.barCellWidth
			color: root.barColor
		}

		Rectangle {
			anchors.left: parent.left
			anchors.leftMargin: root.filled * Theme.barCellWidth
			anchors.right: parent.right
			anchors.top: parent.top
			anchors.bottom: parent.bottom
			color: Theme.dim
		}
	}
}
