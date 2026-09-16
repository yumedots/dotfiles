import QtQuick
import qs

Item {
	id: root

	property alias model: list.model
	property alias delegate: list.delegate
	property int currentIndex: -1
	property int visibleRows: 5
	property real rowHeight: 0
	property real rowSpacing: Config.procsGap
	property real scrollWidth: Config.scrollbarWidth

	readonly property int count: list.count
	readonly property var current: list.currentItem ? list.currentItem.modelData : null
	readonly property real rowWidth: root.width - root.scrollWidth - root.rowSpacing

	implicitHeight: root.visibleRows * root.rowHeight + root.rowSpacing * Math.max(0, root.visibleRows - 1)
	height: root.implicitHeight

	onCurrentIndexChanged: root.applyIndex()

	function applyIndex() {
		if (list.currentIndex !== root.currentIndex)
			list.currentIndex = root.currentIndex;

		root.ensureVisible(root.currentIndex);
	}

	function move(step) {
		if (list.count === 0) {
			root.currentIndex = -1;
			return;
		}

		const from = root.currentIndex < 0 ? (step > 0 ? 0 : list.count - 1) : root.currentIndex + step;
		root.currentIndex = Math.max(0, Math.min(list.count - 1, from));
	}

	function handleKey(event) {
		if (event.text === "j")
			root.move(1);
		else if (event.text === "k")
			root.move(-1);
		else if (event.text === "l")
			root.move(root.visibleRows);
		else if (event.text === "h")
			root.move(-root.visibleRows);
		else
			return false;

		event.accepted = true;
		return true;
	}

	function ensureVisible(index) {
		if (index < 0 || root.rowHeight <= 0)
			return;

		const step = root.rowHeight + root.rowSpacing;
		const top = index * step;
		const bottom = top + root.rowHeight;
		const max = Math.max(0, list.contentHeight - list.height);
		let next = list.contentY;

		if (top < list.contentY)
			next = top;
		else if (bottom > list.contentY + list.height)
			next = bottom - list.height;

		list.contentY = Math.max(0, Math.min(max, next));
	}

	onCountChanged: {
		if (list.count === 0)
			root.currentIndex = -1;
		else if (root.currentIndex >= list.count)
			root.currentIndex = list.count - 1;
	}

	ListView {
		id: list

		readonly property real rowWidth: root.rowWidth
		readonly property real rowHeight: root.rowHeight

		anchors.fill: parent
		anchors.rightMargin: root.scrollWidth + root.rowSpacing
		clip: true
		spacing: root.rowSpacing
		interactive: false
		boundsBehavior: Flickable.StopAtBounds
		keyNavigationEnabled: false
		highlightFollowsCurrentItem: true
		highlightMoveDuration: 0
		highlightResizeDuration: 0

		onModelChanged: {
			root.applyIndex();
			Qt.callLater(root.applyIndex);
		}

		onCurrentIndexChanged: root.ensureVisible(list.currentIndex)

		highlight: Rectangle {
			color: Config.launcherHighlight
			radius: 0
		}
	}

	Rectangle {
		id: scroll

		visible: list.contentHeight > list.height
		width: root.scrollWidth
		height: Math.max(12, list.height * list.height / Math.max(1, list.contentHeight))
		x: root.width - width
		y: list.contentY / Math.max(1, list.contentHeight - list.height) * (list.height - height)
		radius: 0
		color: Config.muted
	}
}
