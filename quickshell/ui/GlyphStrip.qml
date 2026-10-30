pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.services

Item {
	id: root

	property int count: 1
	property int filled: 0
	property bool glyphs: true
	property var pool: []
	property var marks: []
	property color ink: Config.foreground
	property color emptyColor: Config.launcherSearchBox
	property color filledColor: Config.launcherHighlight
	property real boxWidth: Config.lockBoxWidth
	property real boxHeight: Config.lockBoxHeight
	property real gap: Config.lockBoxGap
	property real glyphSize: Config.lockGlyphSize
	property real nudge: 0

	readonly property int first: Math.max(0, root.filled - root.count)

	implicitWidth: Math.max(0, root.count * root.boxWidth + (root.count - 1) * root.gap)
	implicitHeight: root.boxHeight

	onFilledChanged: root.sync()
	onPoolChanged: root.sync()

	function sync() {
		if (!root.glyphs || root.pool.length === 0) {
			root.marks = [];
			return;
		}

		const next = root.marks.slice(0, Math.min(root.filled, root.marks.length));

		while (next.length < root.filled) {
			let pick = root.pool[Math.floor(Math.random() * root.pool.length)];

			if (root.pool.length > 1) {
				let guard = 0;

				while ((next.indexOf(pick) >= 0 || pick === next[next.length - 1]) && guard < 60) {
					pick = root.pool[Math.floor(Math.random() * root.pool.length)];
					guard += 1;
				}
			}

			next.push(pick);
		}

		root.marks = next;
	}

	function reject() {
		shake.restart();
	}

	SequentialAnimation {
		id: shake

		NumberAnimation { target: root; property: "nudge"; to: -7; duration: 40; easing.type: Easing.OutQuad }
		NumberAnimation { target: root; property: "nudge"; to: 7; duration: 60; easing.type: Easing.InOutQuad }
		NumberAnimation { target: root; property: "nudge"; to: -4; duration: 50; easing.type: Easing.InOutQuad }
		NumberAnimation { target: root; property: "nudge"; to: 0; duration: 45; easing.type: Easing.OutCubic }
	}

	Row {
		x: root.nudge
		spacing: root.gap

		Repeater {
			model: root.count

			delegate: Rectangle {
				id: box

				required property int index

				readonly property int slot: root.first + box.index
				readonly property bool lit: box.slot < root.filled

				width: root.boxWidth
				height: root.boxHeight
				color: box.lit ? root.filledColor : root.emptyColor

				TextMetrics {
					id: metrics

					font.family: Config.fontFamily
					font.pixelSize: root.glyphSize
					font.weight: Font.Medium
					text: root.marks[box.slot] || ""
				}

				Text {
					visible: box.lit && root.glyphs
					x: (root.boxWidth - metrics.tightBoundingRect.width) / 2 - metrics.tightBoundingRect.x
					y: (root.boxHeight - metrics.tightBoundingRect.height) / 2 - metrics.tightBoundingRect.y + metrics.boundingRect.y
					font.family: Config.fontFamily
					font.pixelSize: root.glyphSize
					font.weight: Font.Medium
					color: root.ink
					text: metrics.text
				}

				Rectangle {
					visible: box.lit && !root.glyphs
					anchors.centerIn: parent
					width: 5
					height: 5
					color: root.ink
				}
			}
		}
	}
}
