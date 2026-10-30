import QtQuick
import qs
import qs.services

Item {
	id: root

	property var pool: Config.lockGlyphPool
	property real strength: 1
	property real phase: 0

	readonly property int count: Math.max(36, Math.round(root.width / 18))

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

			readonly property real px: root.hash(index * 49297 + 9301)
			readonly property real pu: root.hash(index * 6271 + 31337)
			readonly property real speed: 0.6 + root.hash(index * 2411 + 97) * 0.65
			readonly property real rise: (pu + root.phase * speed) % 1

			x: px * (root.width - width) + Math.sin(root.phase * 1.7 + index) * 18
			y: (1 - rise) * (root.height + 160) - 80
			font.family: Config.fontFamily
			font.pixelSize: 11 + (index * 29) % 14
			color: Qt.hsla(0.02 + root.hash(index * 71 + 13) * 0.11, 0.85, 0.6)
			opacity: root.strength * (0.5 + root.hash(index * 41 + 23) * 0.45)
			text: root.pool.length > 0 ? root.pool[(index * 11 + 5) % root.pool.length] : ""
		}
	}
}
