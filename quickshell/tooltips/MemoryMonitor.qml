import QtQuick
import Quickshell
import Quickshell.Io
import qs.ui
import qs

Item {
	id: root

	property var source: null
	property var procs: []

	readonly property var mem: root.source ? root.source.memory : null
	readonly property real pct: root.mem ? root.mem.pct : 0

	readonly property bool onScreen: root.Window.window ? root.Window.window.visible : false

	implicitWidth: Config.memoryTooltipWidth + Config.memoryTooltipPadding * 2
	implicitHeight: column.implicitHeight + Config.memoryTooltipPadding * 2

	onOnScreenChanged: {
		if (root.onScreen && root.source && root.source.refresh)
			root.source.refresh();
	}

	function dangerColorFor(load) {
		return Helpers.dangerColor(Config.memoryBase, Config.memoryWarn, Config.memoryDanger, Config.memoryWarnAt, Config.memoryDangerAt, load);
	}

	function usage() {
		const m = root.mem;

		if (!m)
			return [];

		const rows = [
			{ label: "used", text: Helpers.sizeText(m.used), color: root.dangerColorFor(root.pct) },
			{ label: "cached", text: Helpers.sizeText(m.cached), color: Config.memoryCached },
			{ label: "buffers", text: Helpers.sizeText(m.buffers), color: Config.memoryBuffers }
		];

		if (m.swapTotal > 0)
			rows.push({ label: "swap", text: Helpers.sizeText(m.swapUsed) + " of " + Helpers.sizeText(m.swapTotal), color: Config.memorySwap });

		rows.push({ label: "free", text: Helpers.sizeText(m.free), color: Config.foreground });

		return rows;
	}

	function segments() {
		const m = root.mem;

		if (!m || m.pool <= 0)
			return [];

		const divider = m.swapTotal > 0 ? Config.memorySeparator : 0;
		const parts = [
			{ value: m.used, color: root.dangerColorFor(root.pct) },
			{ value: m.cached, color: Config.memoryCached },
			{ value: m.buffers, color: Config.memoryBuffers },
			{ value: m.ramFree, color: Config.memoryFree }
		];

		if (divider > 0) {
			parts.push({ value: 0, color: Config.surfaceTranslucent, divider: divider });
			parts.push({ value: m.swapUsed, color: Config.memorySwap });
			parts.push({ value: m.swapFree, color: Config.memoryFree });
		}

		const width = Config.memoryTooltipWidth - divider;
		let x = 0;

		return parts.map(function (part) {
			const out = {
				x: x,
				width: part.divider ? part.divider : width * part.value / m.pool,
				color: part.color
			};

			x += out.width;
			return out;
		});
	}

	function shareOf(kb) {
		if (!root.mem || root.mem.pool <= 0)
			return 0;

		return Math.max(0, Math.min(100, 100 * kb / root.mem.pool));
	}

	Process {
		id: ramProcesses

		command: ["ps", "-eo", "rss=,comm=", "--sort=-rss"]

		function reload() {
			if (!ramProcesses.running)
				ramProcesses.running = true;
		}

		stdout: StdioCollector {
			onStreamFinished: root.procs = Helpers.topProcesses(Helpers.parseTopProcesses(text), Config.psIgnore, Config.memoryTopMax)
		}
	}

	Timer {
		interval: Config.cpuPollMs * 2
		running: root.onScreen
		repeat: true
		triggeredOnStart: true
		onTriggered: ramProcesses.reload()
	}

	Column {
		id: column

		x: Config.memoryTooltipPadding
		y: Config.memoryTooltipPadding
		width: Config.memoryTooltipWidth
		spacing: 6

		Item {
			width: column.width
			height: Math.max(memoryTitle.implicitHeight, memoryTotal.implicitHeight)

			Text {
				id: memoryTitle

				width: parent.width - memoryTotal.width - 8
				elide: Text.ElideRight

				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
				color: Config.foreground
				text: "Memory"
			}

			Text {
				id: memoryTotal

				anchors.right: parent.right

				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
				color: root.dangerColorFor(root.pct)
				text: Math.round(root.pct) + "%"
			}
		}

		Text {
			width: column.width
			elide: Text.ElideRight
			visible: root.mem !== null

			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: Config.memoryBase
			text: root.mem ? Helpers.sizeText(root.mem.committed) + " of " + Helpers.sizeText(root.mem.pool) : ""
		}

		Item {
			width: column.width
			height: 8
			visible: root.mem !== null

			Repeater {
				model: root.segments()

				delegate: Rectangle {
					required property var modelData

					x: modelData.x
					width: modelData.width
					height: parent.height
					color: modelData.color
				}
			}
		}

		Repeater {
			model: root.usage()

			delegate: Item {
				required property var modelData

				width: column.width
				height: Math.max(segmentLabel.implicitHeight, segmentValue.implicitHeight)

				Text {
					id: segmentLabel

					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: modelData.color
					text: modelData.label
				}

				Text {
					id: segmentValue

					anchors.right: parent.right

					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: modelData.color
					text: modelData.text
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
			color: Config.memoryBase
			text: Config.topProcessTitle
		}

		ProcessList {
			width: column.width
			visibleRows: Config.memoryTopCount
			visible: root.procs.length > 0
			model: root.procs

			delegate: Item {
				required property var modelData

				width: ListView.view.rowWidth
				height: ListView.view.rowHeight

				Text {
					id: process

					width: parent.width - amount.width - 8
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: Config.foreground
					text: modelData.name
				}

				Text {
					id: amount

					anchors.right: parent.right

					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: root.dangerColorFor(root.shareOf(modelData.value))
					text: Helpers.sizeText(modelData.value)
				}
			}
		}
	}
}
