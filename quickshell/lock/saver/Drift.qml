import QtQuick
import qs
import qs.services

Item {
	id: root

	property var pool: Config.lockGlyphPool
	property real strength: 1
	property real phase: 0

	readonly property int count: Math.max(40, Math.round(root.height / 10))
	readonly property int lanes: Math.max(8, Math.round(root.height / 48))

	function hash(value) {
		let x = value | 0;

		x = Math.imul(x ^ (x >>> 16), 2246822507);
		x = Math.imul(x ^ (x >>> 13), 3266489909);

		return ((x ^ (x >>> 16)) >>> 0) / 4294967296;
	}

	NumberAnimation on phase {
		from: 0
		to: 3600
		duration: 24000000
		loops: Animation.Infinite
	}

	Repeater {
		model: root.count

		delegate: Text {
			required property int index

			readonly property int lane: index % root.lanes
			readonly property bool forward: index % 2 === 0
			readonly property real pu: root.hash(index * 9301 + 7919)
			readonly property real speed: 0.55 + root.hash(index * 3571 + 29) * 0.7
			readonly property real run: (pu + root.phase * speed) % 1

			x: (forward ? run : 1 - run) * (root.width + 160) - 80
			y: lane * (root.height / root.lanes) + (root.hash(index * 17 + 3) - 0.5) * 18
			font.family: Config.fontFamily
			font.pixelSize: 10 + (index * 41) % 16
			color: Qt.hsla(0.5 + root.hash(index * 89 + 19) * 0.35, 0.7, 0.64)
			opacity: root.strength * (0.45 + root.hash(index * 29 + 11) * 0.5)
			text: root.pool.length > 0 ? root.pool[(index * 13 + 7) % root.pool.length] : ""
		}
	}
}
