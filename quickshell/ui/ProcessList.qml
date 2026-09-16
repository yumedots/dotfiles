import QtQuick
import qs

Item {
	id: root

	property alias model: list.model
	property alias delegate: list.delegate
	property alias currentIndex: list.currentIndex
	property int visibleRows: 5
	property string killKey: Config.procKillKey

	readonly property var current: list.current
	readonly property int count: list.count
	readonly property real rowHeight: prototype.implicitHeight
	readonly property real rowWidth: list.rowWidth

	implicitHeight: root.visibleRows * root.rowHeight + Config.procsGap * Math.max(0, root.visibleRows - 1)
	height: root.implicitHeight

	function move(step) {
		list.move(step);
	}

	function handleKey(event) {
		if (event.text === root.killKey) {
			if (list.current)
				root.killRequested(list.current);
			return true;
		}

		return list.handleKey(event);
	}

	signal killRequested(var proc)

	Text {
		id: prototype

		visible: false
		font.family: Config.fontFamily
		font.pixelSize: Config.fontSize
		text: "0.0%"
	}

	Selector {
		id: list

		anchors.fill: parent
		visibleRows: root.visibleRows
		rowHeight: prototype.implicitHeight
		rowSpacing: Config.procsGap
	}
}
