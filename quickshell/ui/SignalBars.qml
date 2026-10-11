import QtQuick
import qs

Item {
	id: bars

	property int count: 0
	property int total: Config.networkBarCount
	property color ink: Config.foreground
	property color off: Config.networkBarsOff
	property real barWidth: Config.networkBarWidth
	property real gap: Config.networkBarGap
	property real step: Config.networkBarStep

	implicitWidth: bars.total * (bars.barWidth + bars.gap) - bars.gap
	implicitHeight: bars.total * bars.step

	Repeater {
		model: bars.total

		delegate: Rectangle {
			required property int index

			x: index * (bars.barWidth + bars.gap)
			width: bars.barWidth
			height: (index + 1) * bars.step
			anchors.bottom: parent.bottom
			radius: bars.barWidth / 2
			color: index < bars.count ? bars.ink : bars.off
		}
	}
}
