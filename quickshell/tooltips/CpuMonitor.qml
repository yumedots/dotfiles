import QtQuick
import Quickshell
import Quickshell.Io
import "../ui"
import "../config.js" as Config
import "../lib/helpers.js" as Helpers

Item {
	id: root

	property var source: null
	property var info: ({ model: "", cores: 0, threads: 0, mhz: 0, cache: 0 })
	property var procs: []

	readonly property real pct: root.source ? root.source.pct : 0
	readonly property var cores: root.source && root.source.cores ? root.source.cores : []

	readonly property bool onScreen: root.Window.window ? root.Window.window.visible : false
	readonly property real blockSize: (Config.cpuTooltipWidth - (Config.cpuBlockColumns - 1) * Config.cpuBlockGap) / Config.cpuBlockColumns
	readonly property int blockRows: Math.max(1, Math.ceil(root.cores.length / Config.cpuBlockColumns))
	readonly property string spec: Helpers.cpuSpecLine(root.info)

	implicitWidth: Config.cpuTooltipWidth + Config.cpuTooltipPadding * 2
	implicitHeight: column.implicitHeight + Config.cpuTooltipPadding * 2

	onOnScreenChanged: {
		if (root.onScreen && root.source && root.source.refresh)
			root.source.refresh();
	}

	function colorFor(load) {
		return Helpers.mixColors(Config.cpuBase, Config.red, load / 100);
	}

	function blockColor(load) {
		return Helpers.mixColors(Config.cpuIdle, Config.cpuBase, load / 100);
	}

	FileView {
		id: cpuInfoFile

		path: "/proc/cpuinfo"
		blockLoading: true

		onLoaded: root.info = Helpers.parseCpuInfo(cpuInfoFile.text())
	}

	Process {
		id: topProcesses

		command: ["ps", "-eo", "pcpu=,comm=", "--sort=-pcpu"]

		function reload() {
			if (!topProcesses.running)
				topProcesses.running = true;
		}

		stdout: StdioCollector {
			onStreamFinished: root.procs = Helpers.topProcesses(Helpers.parseTopProcesses(text), Config.psIgnore, Config.cpuTopMax)
		}
	}

	Timer {
		interval: Config.cpuPollMs * 2
		running: root.onScreen
		repeat: true
		triggeredOnStart: true
		onTriggered: topProcesses.reload()
	}

	Column {
		id: column

		x: Config.cpuTooltipPadding
		y: Config.cpuTooltipPadding
		width: Config.cpuTooltipWidth
		spacing: 6

		Item {
			width: column.width
			height: Math.max(title.implicitHeight, total.implicitHeight)

			Text {
				id: title

				width: parent.width - total.width - 8
				elide: Text.ElideRight

				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
				color: Config.foreground
				text: root.info.model !== "" ? root.info.model : "CPU"
			}

			Text {
				id: total

				anchors.right: parent.right

				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
				color: root.colorFor(root.pct)
				text: Math.round(root.pct) + "%"
			}
		}

		Text {
			width: column.width
			elide: Text.ElideRight
			visible: text !== ""

			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: Config.cpuBase
			text: root.spec
		}


		Item {
			width: column.width
			height: root.blockRows * (root.blockSize + Config.cpuBlockGap) - Config.cpuBlockGap

			Repeater {
				model: root.cores

				delegate: Rectangle {
					required property real modelData
					required property int index

					readonly property int columnIndex: index % Config.cpuBlockColumns

					x: columnIndex * (root.blockSize + Config.cpuBlockGap)
					y: Math.floor(index / Config.cpuBlockColumns) * (root.blockSize + Config.cpuBlockGap)

					width: root.blockSize
					height: root.blockSize
					radius: 2
					color: root.blockColor(modelData)
				}
			}
		}

		Rectangle {
			width: column.width
			height: 1
			visible: root.procs.length > 0
			color: Config.dim
		}

		Text {
			width: column.width
			visible: root.procs.length > 0

			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: Config.cpuBase
			text: Config.topProcessTitle
		}

		ProcessList {
			width: column.width
			visibleRows: Config.cpuTopCount
			visible: root.procs.length > 0
			model: root.procs

			delegate: Item {
				required property var modelData

				width: ListView.view.rowWidth
				height: ListView.view.rowHeight

				Text {
					id: process

					width: parent.width - percent.width - 8
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: Config.foreground
					text: modelData.name
				}

				Text {
					id: percent

					anchors.right: parent.right

					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: root.colorFor(modelData.value)
					text: modelData.value.toFixed(1) + "%"
				}
			}
		}
	}
}
