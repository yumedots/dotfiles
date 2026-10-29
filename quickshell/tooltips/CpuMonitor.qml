import QtQuick
import qs.ui
import qs
import qs.services

ProcessPanel {
	id: root

	readonly property var sys: Yudae.system.cpu || ({})

	readonly property color accentInk: Config.mono ? Config.cpuBase : Config.cpuBaseMono
	readonly property color peakInk: Config.mono ? Config.cpuPeak : Config.cpuPeakMono
	readonly property var cores: root.source && root.source.cores ? root.source.cores : []
	readonly property real blockSize: (Config.cpuTooltipWidth - (Config.cpuBlockColumns - 1) * Config.cpuBlockGap) / Config.cpuBlockColumns
	readonly property int blockRows: Math.max(1, Math.ceil(root.cores.length / Config.cpuBlockColumns))
	readonly property real vizHeight: root.blockRows * (root.blockSize + Config.cpuBlockGap) - Config.cpuBlockGap

	title: root.sys.model || "CPU"
	detail: root.sys.spec || ""
	detailColor: root.accentInk
	listInk: root.accentInk
	totalInk: root.sys.ink || root.accentInk
	panelWidth: Config.cpuTooltipWidth
	panelPadding: Config.cpuTooltipPadding
	topCount: Config.cpuTopCount
	psField: "pcpu"
	rowColor: (row) => row.color || root.accentInk

	viz: Item {
		width: parent.width
		height: root.vizHeight

		CellGrid {
			values: root.cores
			columns: Config.cpuBlockColumns
			cellSize: root.blockSize
			gap: Config.cpuBlockGap
			colorFor: (value, index) => root.sys.coreInk ? root.sys.coreInk[index] : Config.cpuIdle
		}
	}
}
