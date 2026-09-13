import QtQuick
import "config.js" as Config

Item {
	id: root

	property alias model: list.model
	property alias delegate: list.delegate
	property int visibleRows: 5

	readonly property real scrollWidth: 3
	readonly property real rowHeight: list.rowHeight
	readonly property real rowWidth: list.rowWidth

	implicitHeight: root.visibleRows * root.rowHeight + list.spacing * (root.visibleRows - 1)
	height: root.implicitHeight

	Text {
		id: rowPrototype

		visible: false
		font.family: Config.fontFamily
		font.pixelSize: Config.fontSize
		text: "0.0%"
	}

	ListView {
		id: list

		readonly property real rowHeight: rowPrototype.implicitHeight
		readonly property real rowWidth: root.width - root.scrollWidth - list.spacing

		anchors.fill: parent
		clip: true
		spacing: Config.procsGap
		boundsBehavior: Flickable.StopAtBounds
	}

	Rectangle {
		id: scroll

		visible: list.contentHeight > list.height
		width: root.scrollWidth
		radius: width / 2
		color: Config.muted
		x: root.width - width
		height: Math.max(12, list.height * list.height / Math.max(1, list.contentHeight))
		y: list.contentY / Math.max(1, list.contentHeight - list.height) * (list.height - height)
	}
}
