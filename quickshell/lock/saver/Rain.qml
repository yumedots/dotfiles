import QtQuick
import qs
import qs.services

Item {
	id: root

	property var pool: Config.lockGlyphPool
	property real strength: 1
	property real phase: 0

	readonly property int count: Math.max(48, Math.round(root.width / 14))

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

			readonly property real px: root.hash(index * 9301 + 49297)
			readonly property real pu: root.hash(index * 7919 + 104729)
			readonly property real speed: 0.7 + root.hash(index * 3571 + 71) * 0.7
			readonly property real fall: (pu + root.phase * speed) % 1

			x: px * (root.width - width)
			y: fall * (root.height + 160) - 80
			font.family: Config.fontFamily
			font.pixelSize: 10 + (index * 37) % 14
			color: Qt.hsla(0.34 + root.hash(index * 97 + 5) * 0.14, 0.7, 0.62)
			opacity: root.strength * (0.5 + root.hash(index * 53 + 17) * 0.45)
			text: root.pool.length > 0 ? root.pool[(index * 7 + 3) % root.pool.length] : ""
		}
	}
}
