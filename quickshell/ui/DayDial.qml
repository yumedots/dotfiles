import QtQuick
import QtQuick.Shapes
import qs

Item {
	id: dial

	property date moment: new Date()
	property color dayInk: Config.foreground
	property color nightInk: Config.calendarDialTrack
	property color sunInk: Config.calendarDialSun
	property color moonInk: Config.calendarDialMoon

	readonly property real hours: dial.moment.getHours() + dial.moment.getMinutes() / 60
	readonly property real cx: dial.width / 2
	readonly property real cy: dial.height / 2
	readonly property real ringR: dial.width / 2 - Config.calendarDialRingWidth / 2 - 2
	readonly property bool daylight: dial.hours >= Config.calendarDialDayStart && dial.hours < Config.calendarDialDayEnd

	function angleOf(hour) {
		return (hour - 12) * 15 * Math.PI / 180;
	}

	function onRing(hour) {
		return dial.cx + Math.sin(dial.angleOf(hour)) * dial.ringR;
	}

	function ringY(hour) {
		return dial.cy - Math.cos(dial.angleOf(hour)) * dial.ringR;
	}

	function arcPoints(start) {
		const out = [];
		const steps = 48;

		for (let i = 0; i <= steps; i++) {
			const a = (start + 180 * i / steps) * Math.PI / 180;

			out.push(Qt.point(dial.cx + Math.cos(a) * dial.ringR, dial.cy - Math.sin(a) * dial.ringR));
		}

		return out;
	}

	implicitWidth: Config.calendarDialSize
	implicitHeight: Config.calendarDialSize

	Shape {
		id: ring

		anchors.fill: parent
		preferredRendererType: Shape.CurveRenderer
		asynchronous: false

		ShapePath {
			strokeColor: dial.dayInk
			fillColor: "transparent"
			strokeWidth: Config.calendarDialRingWidth
			capStyle: ShapePath.RoundCap

			PathPolyline {
				path: dial.arcPoints(0)
			}
		}

		ShapePath {
			strokeColor: dial.nightInk
			fillColor: "transparent"
			strokeWidth: Config.calendarDialRingWidth
			capStyle: ShapePath.RoundCap

			PathPolyline {
				path: dial.arcPoints(180)
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

		visible: dial.daylight
		x: dial.onRing(dial.hours) - sunMetrics.tightBoundingRect.width / 2
		y: dial.ringY(dial.hours) - sunMetrics.tightBoundingRect.height / 2
		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialGlyphSize
		color: dial.sunInk
		text: Config.calendarIconSun
	}

	Text {
		id: moonMark

		visible: !dial.daylight
		x: dial.onRing(dial.hours) - moonMetrics.tightBoundingRect.width / 2
		y: dial.ringY(dial.hours) - moonMetrics.tightBoundingRect.height / 2 - Config.calendarDialMoonLift
		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialGlyphSize
		color: dial.moonInk
		text: Config.calendarIconMoon
	}

	Text {
		anchors.centerIn: parent
		width: parent.width
		horizontalAlignment: Text.AlignHCenter

		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialValueSize
		color: dial.dayInk
		text: Qt.formatTime(dial.moment, "HH:mm")
	}
}
