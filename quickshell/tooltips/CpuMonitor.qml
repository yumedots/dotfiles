import QtQuick
import qs.ui
import qs
import qs.services

ProcessPanel {
	id: root

	readonly property var sys: Yudae.system.cpu || ({})

	readonly property color accentInk: Util.pick(Config.mono, Config.cpuBase, Config.cpuBaseMono)
	readonly property color peakInk: Util.pick(Config.mono, Config.cpuPeak, Config.cpuPeakMono)
	readonly property var cores: root.source && root.source.cores ? root.source.cores : []
	readonly property real blockSize: (Config.cpuTooltipWidth - (Config.cpuBlockColumns - 1) * Config.cpuBlockGap) / Config.cpuBlockColumns
	readonly property int blockRows: Math.max(1, Math.ceil(root.cores.length / Config.cpuBlockColumns))
	readonly property real vizHeight: root.blockRows * (root.blockSize + Config.cpuBlockGap) - Config.cpuBlockGap

	title: root.sys.model || "CPU"
	detail: root.sys.spec || ""
	detailColor: root.accentInk
	listInk: root.accentInk
	totalInk: root.colorFor(root.pct)
	panelWidth: Config.cpuTooltipWidth
	panelPadding: Config.cpuTooltipPadding
	topCount: Config.cpuTopCount
	psField: "pcpu"
	rowColor: (value) => root.colorFor(value)

	function colorFor(load) {
		return Ink.mixColors(root.accentInk, root.peakInk, load / 100);
	}

	function blockColor(load) {
		return Ink.mixColors(Config.cpuIdle, root.accentInk, load / 100);
	}

	viz: Item {
		width: parent.width
		height: root.vizHeight

		CellGrid {
			values: root.cores
			columns: Config.cpuBlockColumns
			cellSize: root.blockSize
			gap: Config.cpuBlockGap
			colorFor: function (value) { return root.blockColor(value); }
		}
	}
}
