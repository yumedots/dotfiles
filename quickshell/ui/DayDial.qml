import QtQuick
import qs

Item {
	id: dial

	property date moment: new Date()
	property color ink: Config.foreground
	property color track: Config.calendarDialTrack
	property color sunInk: Config.calendarDialSun
	property color moonInk: Config.calendarDialMoon

	readonly property real hours: dial.moment.getHours() + dial.moment.getMinutes() / 60
	readonly property real frac: dial.hours / 24
	property real shownFrac: dial.frac

	readonly property real cx: dial.width / 2
	readonly property real cy: dial.height / 2
	readonly property real ringR: dial.width / 2 - Config.calendarDialRingWidth / 2 - 2
	readonly property real tickW: 2 * Math.PI * dial.ringR / Config.calendarDialTicks - Config.calendarDialTickGap

	function angleOf(hour) {
		return (hour - 12) * 15 * Math.PI / 180;
	}

	function daylight(hour) {
		return hour >= Config.calendarDialDayStart && hour < Config.calendarDialDayEnd;
	}

	function onRing(hour) {
		const a = dial.angleOf(hour);

		return dial.cx + Math.sin(a) * dial.ringR;
	}

	function ringY(hour) {
		return dial.cy - Math.cos(dial.angleOf(hour)) * dial.ringR;
	}

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
				rotation: (index - 12) * 15
				visible: index !== Config.calendarDialDayStart && index !== Config.calendarDialDayEnd

				Rectangle {
					x: dial.cx - width / 2
					y: dial.cy - dial.ringR - height / 2
					width: dial.tickW
					height: Config.calendarDialRingWidth
					color: dial.daylight(index) ? dial.ink : dial.track
				}
			}
		}
	}

	TextMetrics {
		id: sunMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialGlyphSize
		text: Config.calendarIconSun
	}

	TextMetrics {
		id: moonMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialGlyphSize
		text: Config.calendarIconMoon
	}

	Text {
		id: sunMark

		x: dial.onRing(Config.calendarDialDayStart) - sunMetrics.tightBoundingRect.width / 2 - sunMetrics.tightBoundingRect.x
		y: dial.ringY(Config.calendarDialDayStart) - sunMetrics.tightBoundingRect.height / 2 - sunMetrics.tightBoundingRect.y
		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialGlyphSize
		color: dial.sunInk
		text: Config.calendarIconSun
	}

	Text {
		id: moonMark

		x: dial.onRing(Config.calendarDialDayEnd) - moonMetrics.tightBoundingRect.width / 2 - moonMetrics.tightBoundingRect.x
		y: dial.ringY(Config.calendarDialDayEnd) - moonMetrics.tightBoundingRect.height / 2 - moonMetrics.tightBoundingRect.y
		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialGlyphSize
		color: dial.moonInk
		text: Config.calendarIconMoon
	}

	Item {
		width: dial.width
		height: dial.height
		transformOrigin: Item.Center
		rotation: (dial.shownFrac - 0.5) * 360

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
