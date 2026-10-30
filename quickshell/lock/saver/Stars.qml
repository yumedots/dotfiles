import QtQuick
import qs
import qs.services

Item {
	id: root

	property real strength: 1
	property real phase: 0

	readonly property int count: 180
	readonly property real reach: Math.sqrt(root.width * root.width + root.height * root.height) / 2

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

		delegate: Rectangle {
			required property int index

			readonly property real angle: root.hash(index * 9301 + 17) * Math.PI * 2
			readonly property real speed: 0.5 + root.hash(index * 7919 + 3) * 1.1
			readonly property real depth: (root.hash(index * 3571 + 11) + root.phase * speed) % 1
			readonly property real distance: depth * root.reach
			readonly property real size: 1 + depth * 5

			x: root.width / 2 + Math.cos(angle) * distance - width / 2
			y: root.height / 2 + Math.sin(angle) * distance - height / 2
			width: size
			height: size
			radius: size / 2
			color: Qt.hsla(0.55 + root.hash(index * 2411 + 7) * 0.35, 0.8, 0.55 + depth * 0.35)
			opacity: root.strength * (0.2 + depth * 0.8)
		}
	}
}
