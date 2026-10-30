pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.services

Item {
	id: root

	property var pool: Config.lockGlyphPool
	property real phase

	readonly property int count: Math.max(26, Math.round(root.width / 42))

	opacity: Config.lockSaverOpacity

	NumberAnimation on phase {
		from: 0
		to: 1
		duration: 34000
		loops: Animation.Infinite
	}

	Repeater {
		model: root.count

		delegate: Text {
			required property int index

			readonly property real unit: ((index * 49297 + 9301) % 233280) / 233280
			readonly property real speed: 0.25 + ((index * 6271) % 100) / 140
			readonly property real rise: (unit + root.phase * speed) % 1

			x: unit * (root.width - width) + Math.sin(root.phase * 6.28 + index) * 14
			y: (1 - rise) * (root.height + 160) - 80
			font.family: Config.fontFamily
			font.pixelSize: 10 + (index * 29) % 14
			color: Config.foreground
			opacity: 0.4 + ((index * 41) % 40) / 100
			text: root.pool.length > 0 ? root.pool[(index * 11 + 5) % root.pool.length] : ""
		}
	}
}
