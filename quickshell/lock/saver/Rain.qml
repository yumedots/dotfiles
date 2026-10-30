pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.services

Item {
	id: root

	property var pool: Config.lockGlyphPool
	property real phase

	readonly property int count: Math.max(24, Math.round(root.width / 38))

	opacity: Config.lockSaverOpacity

	NumberAnimation on phase {
		from: 0
		to: 1
		duration: 26000
		loops: Animation.Infinite
	}

	Repeater {
		model: root.count

		delegate: Text {
			required property int index

			readonly property real unit: ((index * 9301 + 49297) % 233280) / 233280
			readonly property real speed: 0.3 + ((index * 7919) % 100) / 120
			readonly property real fall: (unit + root.phase * speed) % 1

			x: unit * (root.width - width)
			y: fall * (root.height + 140) - 70
			font.family: Config.fontFamily
			font.pixelSize: 10 + (index * 37) % 12
			color: Config.foreground
			opacity: 0.4 + ((index * 53) % 45) / 100
			text: root.pool.length > 0 ? root.pool[(index * 7 + 3) % root.pool.length] : ""
		}
	}
}
