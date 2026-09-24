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

	function scroll(step) {
		list.contentY = Util.clamp(list.contentY + step, 0, Math.max(0, list.contentHeight - list.height));
	}

	function move(step) {
		if (list.count === 0) {
			root.currentIndex = -1;
			return;
		}

		const from = root.currentIndex < 0 ? (step > 0 ? -1 : 0) : root.currentIndex;

		root.currentIndex = ((from + step) % list.count + list.count) % list.count;
		root.ensureVisible(root.currentIndex);
	}

	function handleKey(event) {
		const step = Input.delta(event, 1, root.visibleRows);

		if (step === 0)
			return false;

		root.move(step);
		event.accepted = true;
		return true;
	}

	function ensureVisible(index) {
		if (index < 0 || root.rowHeight <= 0)
			return;

		const step = root.rowHeight + root.rowSpacing;
		const top = index * step;

		list.contentY = Util.scrollIntoView(list.contentY, list.height, list.contentHeight, top, top + root.rowHeight);
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

		highlight: Highlight {
			fillParent: false
		}

		MouseArea {
			anchors.fill: parent
			acceptedButtons: Qt.NoButton

			onWheel: function (wheel) {
				root.scroll(wheel.angleDelta.y > 0 ? -(root.rowHeight + root.rowSpacing) : (root.rowHeight + root.rowSpacing));
				wheel.accepted = true;
			}
		}
	}

	Scrollbar {
		view: list
		offset: root.rowSpacing
	}
}
