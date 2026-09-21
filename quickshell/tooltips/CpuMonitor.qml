import QtQuick
import Quickshell.Io
import qs.ui
import qs

ProcessPanel {
	id: root

	property var info: ({ model: "", cores: 0, threads: 0, mhz: 0, cache: 0 })

	readonly property color accentInk: Helpers.pick(Config.mono, Config.cpuBase, Config.cpuBaseMono)
	readonly property color peakInk: Helpers.pick(Config.mono, Config.cpuPeak, Config.cpuPeakMono)
	readonly property var cores: root.source && root.source.cores ? root.source.cores : []
	readonly property real blockSize: (Config.cpuTooltipWidth - (Config.cpuBlockColumns - 1) * Config.cpuBlockGap) / Config.cpuBlockColumns
	readonly property int blockRows: Math.max(1, Math.ceil(root.cores.length / Config.cpuBlockColumns))
	readonly property real vizHeight: root.blockRows * (root.blockSize + Config.cpuBlockGap) - Config.cpuBlockGap

	title: root.info.model !== "" ? root.info.model : "CPU"
	detail: Helpers.cpuSpecLine(root.info)
	detailColor: root.accentInk
	listInk: root.accentInk
	totalInk: root.colorFor(root.pct)
	panelWidth: Config.cpuTooltipWidth
	panelPadding: Config.cpuTooltipPadding
	topCount: Config.cpuTopCount
	psField: "pcpu"
	rowText: (value) => value.toFixed(1) + "%"
	rowColor: (value) => root.colorFor(value)

	function colorFor(load) {
		return Helpers.mixColors(root.accentInk, root.peakInk, load / 100);
	}

	function blockColor(load) {
		return Helpers.mixColors(Config.cpuIdle, root.accentInk, load / 100);
	}

	FileView {
		id: cpuInfoFile

		path: "/proc/cpuinfo"
		blockLoading: true

		onLoaded: root.info = Helpers.parseCpuInfo(cpuInfoFile.text())
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
