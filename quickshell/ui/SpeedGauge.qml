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

	readonly property real start: 225
	readonly property real span: 270
	readonly property real cx: gauge.width / 2
	readonly property real cy: gauge.height / 2
	readonly property real ringR: gauge.width / 2 - Config.speedRingWidth / 2 - 3
	readonly property real ringSegW: 2 * Math.PI * gauge.ringR * gauge.span / 360 / Config.speedRingSegs - Config.speedRingGap
	readonly property real frac: gauge.ceiling > 0 ? Math.min(1, Math.max(0, gauge.value / gauge.ceiling)) : 0
	property real shownFrac: frac

	Behavior on shownFrac {
		NumberAnimation {
			duration: 300
			easing.type: Easing.OutQuad
		}
	}

	implicitWidth: Config.speedGaugeSize
	implicitHeight: Config.speedGaugeSize

	Item {
		width: gauge.width
		height: gauge.height

		Repeater {
			model: Config.speedRingSegs

			delegate: Item {
				required property int index

				width: gauge.width
				height: gauge.height
				transformOrigin: Item.Center
				rotation: gauge.start + gauge.span * index / (Config.speedRingSegs - 1)

				Rectangle {
					x: gauge.cx - width / 2
					y: gauge.cy - gauge.ringR - height / 2
					width: gauge.ringSegW
					height: Config.speedRingWidth
					color: gauge.value > 0 && index / (Config.speedRingSegs - 1) <= gauge.shownFrac ? gauge.ink : gauge.track
				}
			}
		}

		Item {
			width: gauge.width
			height: gauge.height
			transformOrigin: Item.Center
			rotation: gauge.start + gauge.span * gauge.shownFrac

			Rectangle {
				x: gauge.cx - width / 2
				y: gauge.cy - Config.speedNeedleBase - Config.speedNeedleLen
				width: Config.speedNeedleWidth
				height: Config.speedNeedleLen
				color: gauge.value > 0 ? gauge.ink : gauge.track
			}
		}

		Column {
			width: gauge.width
			anchors.verticalCenter: parent.verticalCenter
			spacing: 2

			Text {
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
	}
}
