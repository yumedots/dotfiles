import QtQuick
import qs

Item {
	id: gauge

	property real value: 0
	property real ceiling: 1
	property color ink: Config.foreground
	property color track: Config.networkIdle
	property string valueText: ""
	property string unit: Config.networkSpeedUnit
	property string arrow: ""
	property string arrowSide: "right"

	readonly property real start: 225
	readonly property real span: 270
	readonly property real cx: gauge.width / 2
	readonly property real cy: gauge.height / 2
	readonly property real ringR: gauge.width / 2 - Config.speedRingWidth / 2 - 3
	readonly property real ringSegW: 2 * Math.PI * gauge.ringR * gauge.span / 360 / Config.speedRingSegs - Config.speedRingGap
	readonly property real frac: gauge.ceiling > 0 ? Math.min(1, Math.max(0, gauge.value / gauge.ceiling)) : 0
	property real shownFrac: gauge.frac

	Behavior on shownFrac {
		NumberAnimation {
			duration: 450
			easing.type: Easing.OutQuad
		}
	}

	implicitWidth: Config.speedGaugeSize
	implicitHeight: Config.speedGaugeSize

	onShownFracChanged: canvas.requestPaint()

	Canvas {
		id: canvas

		width: gauge.width
		height: gauge.height
		renderStrategy: Canvas.Cooperative

		onWidthChanged: canvas.requestPaint()
		onHeightChanged: canvas.requestPaint()

		onPaint: {
			const ctx = getContext("2d");

			ctx.reset();
			ctx.lineCap = "butt";
			ctx.lineWidth = Config.speedRingWidth;

			const half = gauge.ringSegW / 2 / gauge.ringR;

			for (let i = 0; i < Config.speedRingSegs; i++) {
				const centre = (gauge.start + gauge.span * i / (Config.speedRingSegs - 1)) * Math.PI / 180 - Math.PI / 2;
				const lit = gauge.value > 0 && i / (Config.speedRingSegs - 1) <= gauge.shownFrac;

				ctx.strokeStyle = lit ? gauge.ink : gauge.track;
				ctx.beginPath();
				ctx.arc(gauge.cx, gauge.cy, gauge.ringR, centre - half, centre + half);
				ctx.stroke();
			}

			const a = (gauge.start + gauge.span * gauge.shownFrac) * Math.PI / 180 - Math.PI / 2;
			const reach = Config.speedNeedleBase + Config.speedNeedleLen;
			const tipX = gauge.cx + Math.cos(a) * reach;
			const tipY = gauge.cy + Math.sin(a) * reach;
			const tailX = gauge.cx + Math.cos(a) * Config.speedNeedleBase;
			const tailY = gauge.cy + Math.sin(a) * Config.speedNeedleBase;
			const nx = -Math.sin(a) * Config.speedNeedleWidth / 2;
			const ny = Math.cos(a) * Config.speedNeedleWidth / 2;

			ctx.fillStyle = gauge.value > 0 ? gauge.ink : gauge.track;
			ctx.beginPath();
			ctx.moveTo(tipX - nx, tipY - ny);
			ctx.lineTo(tipX + nx, tipY + ny);
			ctx.lineTo(tailX + nx, tailY + ny);
			ctx.lineTo(tailX - nx, tailY - ny);
			ctx.closePath();
			ctx.fill();
		}
	}

	Column {
		id: readout

		width: gauge.width
		anchors.verticalCenter: parent.verticalCenter
		spacing: 1

		Text {
			id: valueText

			width: parent.width
			horizontalAlignment: Text.AlignHCenter

			font.family: Config.fontFamily
			font.pixelSize: Config.speedValueSize
			color: gauge.ink
			text: gauge.valueText
		}

		Text {
			width: parent.width
			horizontalAlignment: Text.AlignHCenter

			font.family: Config.fontFamily
			font.pixelSize: Config.speedUnitSize
			color: gauge.ink
			opacity: 0.6
			text: gauge.unit
		}
	}

	Text {
		id: sideArrow

		anchors.verticalCenter: valueText.verticalCenter
		anchors.left: gauge.arrowSide === "right" ? valueText.right : undefined
		anchors.right: gauge.arrowSide === "left" ? valueText.left : undefined
		anchors.leftMargin: Config.speedArrowGap
		visible: text !== ""

		font.family: Config.fontFamily
		font.pixelSize: Config.speedArrowSize
		color: gauge.ink
		text: gauge.arrow
	}
}
