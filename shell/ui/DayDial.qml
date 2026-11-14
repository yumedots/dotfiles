import QtQuick
import QtQuick.Shapes
import qs

Item {
	id: dial

	property date moment: new Date()

	readonly property real hours: dial.moment.getHours() + dial.moment.getMinutes() / 60
	readonly property real cx: dial.width / 2
	readonly property real cy: dial.ringR + Config.calendarDialRingWidth / 2
	readonly property real ringR: dial.width / 2 - Config.calendarDialRingWidth / 2 - 2
	readonly property bool daylight: dial.hours >= Config.calendarDialDayStart && dial.hours < Config.calendarDialDayEnd

	function angleOf(hour) {
		return (180 - hour * 7.5) * Math.PI / 180;
	}

	function onRing(hour) {
		return dial.cx + Math.cos(dial.angleOf(hour)) * dial.ringR;
	}

	function ringY(hour) {
		return dial.cy - Math.sin(dial.angleOf(hour)) * dial.ringR;
	}

	function bandPoints() {
		const out = [];
		const steps = 72;
		const outer = dial.ringR + Config.calendarDialRingWidth / 2;
		const inner = dial.ringR - Config.calendarDialRingWidth / 2;

		for (let i = 0; i <= steps; i++) {
			const a = (180 - 180 * i / steps) * Math.PI / 180;

			out.push(Qt.point(dial.cx + Math.cos(a) * outer, dial.cy - Math.sin(a) * outer));
		}

		for (let i = steps; i >= 0; i--) {
			const a = (180 - 180 * i / steps) * Math.PI / 180;

			out.push(Qt.point(dial.cx + Math.cos(a) * inner, dial.cy - Math.sin(a) * inner));
		}

		return out;
	}

	implicitWidth: Config.calendarDialSize
	implicitHeight: dial.cy + Config.calendarDialRingWidth

	Shape {
		id: band

		anchors.fill: parent
		preferredRendererType: Shape.CurveRenderer
		asynchronous: false

		ShapePath {
			strokeColor: "transparent"
			fillColor: "transparent"

			fillGradient: ConicalGradient {
				centerX: dial.cx
				centerY: dial.cy
				angle: 0

				GradientStop { position: 0.0; color: Config.calendarDialNight }
				GradientStop { position: 0.104; color: Config.calendarDialNight }
				GradientStop { position: 0.125; color: Config.calendarDialRed }
				GradientStop { position: 0.146; color: Config.calendarDialOrange }
				GradientStop { position: 0.1875; color: Config.calendarDialYellow }
				GradientStop { position: 0.229; color: Config.calendarDialCream }
				GradientStop { position: 0.25; color: Config.calendarDialNoon }
				GradientStop { position: 0.271; color: Config.calendarDialCream }
				GradientStop { position: 0.3125; color: Config.calendarDialYellow }
				GradientStop { position: 0.354; color: Config.calendarDialDay }
				GradientStop { position: 0.396; color: Config.calendarDialNight }
				GradientStop { position: 0.4375; color: Config.calendarDialNight }
				GradientStop { position: 0.5; color: Config.calendarDialNight }
			}

			PathPolyline {
				path: dial.bandPoints()
			}
		}
	}

	TextMetrics {
		id: sunMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialGlyphSize
		text: Config.glyph("sun")
	}

	TextMetrics {
		id: moonMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialGlyphSize
		text: Config.glyph("moon")
	}

	Icon {
		id: sunMark

		visible: dial.daylight
		x: dial.onRing(dial.hours) - sunMetrics.tightBoundingRect.width / 2
		y: dial.ringY(dial.hours) - sunMetrics.tightBoundingRect.height / 2
		pixelSize: Config.calendarDialGlyphSize
		name: "sun"
	}

	Icon {
		id: moonMark

		visible: !dial.daylight
		x: dial.onRing(dial.hours) - moonMetrics.tightBoundingRect.width / 2
		y: dial.ringY(dial.hours) - moonMetrics.tightBoundingRect.height / 2 - Config.calendarDialMoonLift
		pixelSize: Config.calendarDialGlyphSize
		name: "moon"
	}
}
