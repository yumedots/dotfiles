import QtQuick

ListView {
	id: root

	property int shown: 3
	property int offsetRow: 0
	property real pending: 0

	readonly property int lastRow: Math.max(0, root.count - root.shown)

	clip: true
	interactive: false
	boundsBehavior: Flickable.StopAtBounds

	function goTo(index) {
		root.offsetRow = Math.max(0, Math.min(root.lastRow, index));
		root.positionViewAtIndex(root.offsetRow, ListView.Beginning);
	}

	onCountChanged: root.goTo(root.offsetRow)

	WheelHandler {
		acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

		onWheel: function (event) {
			root.pending += event.angleDelta.y;

			while (Math.abs(root.pending) >= 120) {
				const down = root.pending < 0;
				root.pending += down ? 120 : -120;
				root.goTo(root.offsetRow + (down ? 1 : -1));
			}
		}
	}
}
