import QtQuick
import qs.ui
import qs

ProcessPanel {
	id: root

	property var governors: root.source ? root.source.governors : []
	property string governor: root.source ? root.source.governor : ""

	readonly property color accentInk: Util.pick(Config.mono, Config.powerBase, Config.powerBaseMono)
	readonly property int governorIndex: Math.max(0, root.governors.indexOf(root.governor))

	title: Config.powerGovernorTitle
	showTotal: true
	totalOverride: govStep.hoverLabel !== "" ? govStep.hoverLabel : root.governor
	totalInk: root.accentInk
	showProcessList: false
	listInk: root.accentInk
	panelWidth: Config.powerTooltipWidth
	panelPadding: Config.powerTooltipPadding

	viz: StepBar {
		id: govStep

		width: parent.width
		model: root.governors
		selected: root.governorIndex
		ink: root.accentInk
		onPick: (next) => root.governorPicked(String(next))
	}

	signal governorPicked(string governor)
}
