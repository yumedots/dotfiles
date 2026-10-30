import QtQuick
import qs.ui
import qs

ProcessPanel {
	id: root

	property var governors: root.source ? root.source.governors : []
	property string governor: root.source ? root.source.governor : ""
	property var battery: root.source ? root.source.battery : null

	readonly property color accentInk: Config.mono ? Config.powerBaseMono : Config.powerBase
	readonly property int governorIndex: Math.max(0, root.governors.indexOf(root.governor))

	title: Config.powerGovernorTitle
	showTotal: true
	totalOverride: govStep.hoverLabel !== "" ? govStep.hoverLabel : root.governor
	totalInk: root.accentInk
	showProcessList: false
	listInk: root.accentInk
	panelWidth: Config.powerTooltipWidth
	panelPadding: Config.powerTooltipPadding

	viz: [
		PowerFlow {
			visible: root.battery !== null
			width: parent.width
			height: Config.powerFlowHeight
			flow: !root.battery ? 0 : (root.battery.state === "Charging" ? 1 : (root.battery.state === "Discharging" ? -1 : 0))
			watts: root.battery ? root.battery.watts || 0 : 0
			fill: root.battery ? root.battery.pct / 100 : 1
			hotInk: !Config.mono && root.battery && root.battery.color ? root.battery.color : root.accentInk
		},

		StepBar {
			id: govStep

			width: parent.width
			model: root.governors
			selected: root.governorIndex
			ink: root.accentInk
			onPick: (next) => root.governorPicked(String(next))
		}
	]

	signal governorPicked(string governor)
}
