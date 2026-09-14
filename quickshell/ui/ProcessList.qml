import QtQuick
import qs

Item {
	id: root

	property alias model: list.model
	property alias delegate: list.delegate
	property int visibleRows: 5
	property string killKey: Config.procKillKey

	readonly property var current: list.currentItem ? list.currentItem.modelData : null
	readonly property int count: list.count
	readonly property real scrollWidth: 3
	readonly property real rowHeight: list.rowHeight
	readonly property real rowWidth: list.rowWidth

	implicitHeight: root.visibleRows * root.rowHeight + list.spacing * (root.visibleRows - 1)
	height: root.implicitHeight

	focus: true

	signal killRequested(var proc)

	function move(step) {
		if (list.count === 0) {
			list.currentIndex = -1;
			return;
		}

		const from = list.currentIndex < 0 ? 0 : list.currentIndex + step;
		list.currentIndex = Math.min(Math.max(from, 0), list.count - 1);
		list.positionViewAtIndex(list.currentIndex, ListView.Contain);
	}

	Keys.onUpPressed: root.move(-1)
	Keys.onDownPressed: root.move(1)

	Keys.onPressed: function (event) {
		if (event.text === "j") {
			root.move(1);
			event.accepted = true;
		} else if (event.text === "k") {
			root.move(-1);
			event.accepted = true;
		} else if (event.text === "l") {
			root.move(root.visibleRows);
			event.accepted = true;
		} else if (event.text === "h") {
			root.move(-root.visibleRows);
			event.accepted = true;
		} else if (event.text === root.killKey) {
			if (list.currentItem)
				root.killRequested(list.currentItem.modelData);
			event.accepted = true;
		}
	}

	onCountChanged: {
		if (list.currentIndex >= list.count)
			list.currentIndex = list.count - 1;
	}

	Text {
		id: rowPrototype

		visible: false
		font.family: Config.fontFamily
		font.pixelSize: Config.fontSize
		text: "0.0%"
	}

	Item {
		anchors.fill: parent
		clip: true

		Rectangle {
			visible: list.currentItem !== null
			width: root.width
			height: list.currentItem ? list.currentItem.height : 0
			y: list.currentItem ? list.currentItem.y : 0
			radius: 2
			color: Config.launcherHighlight
		}
	}

	ListView {
		id: list

		readonly property real rowHeight: rowPrototype.implicitHeight
		readonly property real rowWidth: root.width - root.scrollWidth - list.spacing

		anchors.fill: parent
		clip: true
		spacing: Config.procsGap
		boundsBehavior: Flickable.StopAtBounds
		keyNavigationEnabled: false
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
