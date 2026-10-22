import QtQuick
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

	function mix(a, b, k) {
		const ar = parseInt(a.substr(1, 2), 16);
		const ag = parseInt(a.substr(3, 2), 16);
		const ab = parseInt(a.substr(5, 2), 16);
		const br = parseInt(b.substr(1, 2), 16);
		const bg = parseInt(b.substr(3, 2), 16);
		const bb = parseInt(b.substr(5, 2), 16);
		const hex = (v) => Math.round(v).toString(16).padStart(2, "0");

		return "#" + hex(ar + (br - ar) * k) + hex(ag + (bg - ag) * k) + hex(ab + (bb - ab) * k);
	}

	function rampAt(t) {
		const stops = Config.calendarDialRamp;

		for (let i = 1; i < stops.length; i++) {
			if (t <= stops[i][0]) {
				const span = stops[i][0] - stops[i - 1][0];
				const k = span > 0 ? (t - stops[i - 1][0]) / span : 0;

				return dial.mix(stops[i - 1][1], stops[i][1], k);
			}
		}

		return stops[stops.length - 1][1];
	}

	implicitWidth: Config.calendarDialSize
	implicitHeight: dial.cy + Config.calendarDialRingWidth

	Canvas {
		id: band

		width: dial.width
		height: dial.height
		renderStrategy: Canvas.Cooperative

		onPaint: {
			const ctx = getContext("2d");

			ctx.reset();

			const steps = 240;
			const outer = dial.ringR + Config.calendarDialRingWidth / 2;
			const inner = dial.ringR - Config.calendarDialRingWidth / 2;
			const overlap = 0.004;

			for (let i = 0; i < steps; i++) {
				const t0 = i / steps;
				const t1 = (i + 1) / steps;
				const a0 = Math.PI + Math.PI * t0 - overlap;
				const a1 = Math.PI + Math.PI * t1 + overlap;

				ctx.fillStyle = dial.rampAt((t0 + t1) / 2);
				ctx.beginPath();
				ctx.arc(dial.cx, dial.cy, outer, a0, a1);
				ctx.arc(dial.cx, dial.cy, inner, a1, a0, true);
				ctx.closePath();
				ctx.fill();
			}
		}

		Component.onCompleted: band.requestPaint()

		onWidthChanged: band.requestPaint()
		onHeightChanged: band.requestPaint()
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
		color: Config.foreground
		text: Config.calendarIconSun
	}

	Text {
		id: moonMark

		visible: !dial.daylight
		x: dial.onRing(dial.hours) - moonMetrics.tightBoundingRect.width / 2
		y: dial.ringY(dial.hours) - moonMetrics.tightBoundingRect.height / 2 - Config.calendarDialMoonLift
		font.family: Config.fontFamily
		font.pixelSize: Config.calendarDialGlyphSize
		color: Config.foreground
		text: Config.calendarIconMoon
	}
}
