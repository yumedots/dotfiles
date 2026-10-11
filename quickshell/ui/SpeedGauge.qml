import QtQuick
import qs

Item {
	id: gauge

	property real value: 0
	property real ceiling: 1
	property real progress: 0
	property color ink: Config.foreground
	property color track: Config.networkIdle
	property string valueText: ""
	property string unit: Config.networkSpeedUnit

	readonly property real start: 225
	readonly property real span: 270
	readonly property real cx: gauge.width / 2
	readonly property real cy: gauge.height / 2
	readonly property real progR: gauge.width / 2 - Config.speedProgWidth / 2 - 2
	readonly property real ringR: gauge.progR - Config.speedProgWidth - 4 - Config.speedRingWidth / 2
	readonly property real ringSegW: 2 * Math.PI * gauge.ringR * gauge.span / 360 / Config.speedRingSegs - Config.speedRingGap
	readonly property real progSegW: 2 * Math.PI * gauge.progR * gauge.span / 360 / Config.speedProgSegs - Config.speedProgGap
	readonly property real frac: gauge.ceiling > 0 ? Math.min(1, Math.max(0, gauge.value / gauge.ceiling)) : 0

	implicitWidth: Config.speedGaugeSize
	implicitHeight: Config.speedGaugeSize

	Item {
		width: gauge.width
		height: gauge.height

		Repeater {
			model: Config.speedProgSegs

			delegate: Item {
				required property int index

				width: gauge.width
				height: gauge.height
				transformOrigin: Item.Center
				rotation: gauge.start + gauge.span * index / (Config.speedProgSegs - 1)

				Rectangle {
					x: gauge.cx - width / 2
					y: gauge.cy - gauge.progR - height / 2
					width: gauge.progSegW
					height: Config.speedProgWidth
					visible: gauge.progress > 0
					color: gauge.ink
					opacity: index / (Config.speedProgSegs - 1) < gauge.progress ? 0.8 : 0.12
				}
			}
		}

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
					color: index / (Config.speedRingSegs - 1) <= gauge.frac ? gauge.ink : gauge.track
				}
			}
		}

		Item {
			width: gauge.width
			height: gauge.height
			transformOrigin: Item.Center
			rotation: gauge.start + gauge.span * gauge.frac

			Rectangle {
				x: gauge.cx - width / 2
				y: gauge.cy - Config.speedNeedleBase - Config.speedNeedleLen
				width: Config.speedNeedleWidth
				height: Config.speedNeedleLen
				color: gauge.ink
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
