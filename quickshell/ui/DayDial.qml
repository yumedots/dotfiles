import QtQuick
import qs

Item {
	id: dial

	property date moment: new Date()
	property color ink: Config.foreground
	property color track: Config.calendarDialTrack

	readonly property real hours: dial.moment.getHours() + dial.moment.getMinutes() / 60
	readonly property real frac: dial.hours / 24
	property real shownFrac: dial.frac

	readonly property real start: 225
	readonly property real span: 270
	readonly property real cx: dial.width / 2
	readonly property real cy: dial.height / 2
	readonly property real ringR: dial.width / 2 - Config.calendarDialRingWidth / 2 - 2
	readonly property real tickW: 2 * Math.PI * dial.ringR * dial.span / 360 / Config.calendarDialTicks - Config.calendarDialTickGap

	Behavior on shownFrac {
		NumberAnimation {
			duration: 450
			easing.type: Easing.OutQuad
		}
	}

	implicitWidth: Config.calendarDialSize
	implicitHeight: Config.calendarDialSize

	Item {
		width: dial.width
		height: dial.height

		Repeater {
			model: Config.calendarDialTicks

			delegate: Item {
				required property int index

				width: dial.width
				height: dial.height
				transformOrigin: Item.Center
				rotation: dial.start + dial.span * index / Config.calendarDialTicks

				Rectangle {
					x: dial.cx - width / 2
					y: dial.cy - dial.ringR - height / 2
					width: dial.tickW
					height: Config.calendarDialRingWidth
					color: index < dial.hours ? dial.ink : dial.track
				}
			}
		}
	}

	Item {
		width: dial.width
		height: dial.height
		transformOrigin: Item.Center
		rotation: dial.start + dial.span * dial.shownFrac

		Rectangle {
			x: dial.cx - width / 2
			y: dial.cy - Config.calendarDialNeedleBase - Config.calendarDialNeedleLen
			width: Config.calendarDialNeedleWidth
			height: Config.calendarDialNeedleLen
			color: dial.ink
		}
	}
	Text {
		anchors.centerIn: parent
		width: parent.width
		horizontalAlignment: Text.AlignHCenter

		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialValueSize
		color: dial.ink
		text: Qt.formatTime(dial.moment, "HH:mm")
	}
}
