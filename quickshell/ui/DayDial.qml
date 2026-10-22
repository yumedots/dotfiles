import QtQuick
import QtQuick.Shapes
import qs

Item {
	id: dial

	property int variant: Config.calendarDialVariant
	property date moment: new Date()
	property color dayInk: Config.foreground
	property color nightInk: Config.calendarDialTrack
	property color sunInk: Config.calendarDialSun
	property color moonInk: Config.calendarDialMoon

	readonly property bool arc: dial.variant === 2
	readonly property color markInk: dial.arc ? Config.foreground : (dial.daylight ? dial.sunInk : dial.moonInk)
	readonly property real hours: dial.moment.getHours() + dial.moment.getMinutes() / 60
	readonly property real cx: dial.width / 2
	readonly property real cy: dial.arc ? dial.ringR + Config.calendarDialRingWidth / 2 : dial.height / 2
	readonly property real ringR: dial.width / 2 - Config.calendarDialRingWidth / 2 - 2
	readonly property bool daylight: dial.hours >= Config.calendarDialDayStart && dial.hours < Config.calendarDialDayEnd

	function toggle() {
		dial.variant = dial.variant === 2 ? 1 : 2;
	}

	function angleOf(hour) {
		if (dial.arc)
			return (180 - hour * 7.5) * Math.PI / 180;

		return (hour - 12) * 15 * Math.PI / 180;
	}

	function onRing(hour) {
		return dial.cx + Math.cos(dial.angleOf(hour)) * dial.ringR;
	}

	function ringY(hour) {
		return dial.cy - Math.sin(dial.angleOf(hour)) * dial.ringR;
	}

	function arcPoints(from, to) {
		const out = [];
		const steps = 72;

		for (let i = 0; i <= steps; i++) {
			const a = (from + (to - from) * i / steps) * Math.PI / 180;

			out.push(Qt.point(dial.cx + Math.cos(a) * dial.ringR, dial.cy - Math.sin(a) * dial.ringR));
		}

		return out;
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
	implicitHeight: dial.arc ? dial.cy + 26 : Config.calendarDialSize

	Shape {
		id: ring

		anchors.fill: parent
		visible: !dial.arc
		preferredRendererType: Shape.CurveRenderer
		asynchronous: false

		ShapePath {
			strokeColor: dial.dayInk
			fillColor: "transparent"
			strokeWidth: Config.calendarDialRingWidth
			capStyle: ShapePath.RoundCap

			PathPolyline {
				path: dial.arcPoints(0, 180)
			}
		}

		ShapePath {
			strokeColor: dial.nightInk
			fillColor: "transparent"
			strokeWidth: Config.calendarDialRingWidth
			capStyle: ShapePath.RoundCap

			PathPolyline {
				path: dial.arcPoints(180, 360)
			}
		}
	}

	Shape {
		id: band

		anchors.fill: parent
		visible: dial.arc
		preferredRendererType: Shape.CurveRenderer
		asynchronous: false

		ShapePath {
			strokeColor: "transparent"
			fillColor: "transparent"

			fillGradient: ConicalGradient {
				centerX: dial.cx
				centerY: dial.cy
				angle: 0

				GradientStop { position: 0.0; color: "#2b4a94" }
				GradientStop { position: 0.104; color: "#2b4a94" }
				GradientStop { position: 0.125; color: "#d14a3c" }
				GradientStop { position: 0.146; color: "#e8873a" }
				GradientStop { position: 0.1875; color: "#f2c14e" }
				GradientStop { position: 0.229; color: "#f7e3a1" }
				GradientStop { position: 0.25; color: "#fdf3cf" }
				GradientStop { position: 0.271; color: "#f7e3a1" }
				GradientStop { position: 0.3125; color: "#f2c14e" }
				GradientStop { position: 0.354; color: "#e8873a" }
				GradientStop { position: 0.396; color: "#d14a3c" }
				GradientStop { position: 0.4375; color: "#2b4a94" }
				GradientStop { position: 0.5; color: "#2b4a94" }
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
		color: dial.markInk
		text: Config.calendarIconSun
	}

	Text {
		id: moonMark

		visible: !dial.daylight
		x: dial.onRing(dial.hours) - moonMetrics.tightBoundingRect.width / 2
		y: dial.ringY(dial.hours) - moonMetrics.tightBoundingRect.height / 2 - Config.calendarDialMoonLift
		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialGlyphSize
		color: dial.markInk
		text: Config.calendarIconMoon
	}

	Text {
		id: readout

		anchors.horizontalCenter: parent.horizontalCenter
		y: dial.cy + (dial.arc ? 4 : -8)
		width: parent.width
		horizontalAlignment: Text.AlignHCenter

		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialValueSize
		color: Config.foreground
		text: Qt.formatTime(dial.moment, "HH:mm")
	}
}
