pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.services

Item {
	id: root

	property int count: 1
	property int filled: 0
	property bool glyphs: true
	property bool animate: true
	property var pool: []
	property int seed: 1
	property color ink: Config.foreground
	property color emptyColor: Config.launcherSearchBox
	property color filledColor: Config.launcherHighlight
	property real boxWidth: Config.lockBoxWidth
	property real boxHeight: Config.lockBoxHeight
	property real gap: Config.lockBoxGap
	property real glyphSize: Config.lockGlyphSize

	readonly property int first: Math.max(0, root.filled - root.count)

	implicitWidth: Math.max(0, root.count * root.boxWidth + (root.count - 1) * root.gap)
	implicitHeight: root.boxHeight

	function mix(value) {
		let x = value | 0;

		x = Math.imul(x ^ (x >>> 16), 2246822507);
		x = Math.imul(x ^ (x >>> 13), 3266489909);

		return (x ^ (x >>> 16)) >>> 0;
	}

	function glyphFor(slot) {
		if (root.pool.length === 0)
			return "";

		return root.pool[root.mix(root.seed * 2654435761 + slot * 7919) % root.pool.length];
	}

	function shuffle() {
		root.seed = root.seed + 1;
	}

	function reject() {
		root.shuffle();
		shake.restart();
	}

	SequentialAnimation {
		id: shake

		NumberAnimation { target: root; property: "nudge"; to: -7; duration: 40; easing.type: Easing.OutQuad }
		NumberAnimation { target: root; property: "nudge"; to: 7; duration: 60; easing.type: Easing.InOutQuad }
		NumberAnimation { target: root; property: "nudge"; to: -4; duration: 50; easing.type: Easing.InOutQuad }
		NumberAnimation { target: root; property: "nudge"; to: 0; duration: 45; easing.type: Easing.OutCubic }
	}

	property real nudge: 0

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
				property int scramble: 0

				width: root.boxWidth
				height: root.boxHeight
				radius: 2
				color: box.lit ? root.filledColor : root.emptyColor
				scale: box.lit ? 1 : 0.94

				Behavior on color {
					ColorAnimation { duration: root.animate ? 120 : 0 }
				}

				Behavior on scale {
					NumberAnimation { duration: root.animate ? 170 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.45 }
				}

				Text {
					id: glyph

					anchors.fill: parent
					visible: box.lit && root.glyphs
					horizontalAlignment: Text.AlignHCenter
					verticalAlignment: Text.AlignVCenter
					font.family: Config.fontFamily
					font.pixelSize: root.glyphSize
					font.weight: Font.Medium
					color: root.ink
					opacity: box.lit ? 1 : 0
					text: box.scramble > 0 ? root.glyphFor(box.slot + box.scramble * 131) : root.glyphFor(box.slot)

					Behavior on opacity {
						NumberAnimation { duration: root.animate ? 130 : 0 }
					}
				}

				Rectangle {
					visible: box.lit && !root.glyphs
					anchors.centerIn: parent
					width: 5
					height: 5
					radius: 2.5
					color: root.ink
				}

				Timer {
					interval: 32
					repeat: true
					running: box.scramble > 0

					onTriggered: box.scramble = box.scramble - 1
				}

				onLitChanged: {
					if (!box.lit || !root.animate)
						return;

					box.scramble = 3;
				}
			}
		}
	}
}
