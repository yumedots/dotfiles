import QtQuick
import qs.ui
import qs
import qs.services

ProcessPanel {
	id: root

	property var mem: root.source ? root.source.memory : null

	readonly property color accentInk: Config.mono ? Config.memoryBase : Config.memoryBaseMono
	readonly property color cachedInk: Config.mono ? Config.memoryCached : Config.memoryCachedMono
	readonly property color buffersInk: Config.mono ? Config.memoryBuffers : Config.memoryBuffersMono
	readonly property color warnInk: Config.mono ? Config.memoryWarn : Config.memoryWarnMono
	readonly property color dangerInk: Config.mono ? Config.memoryDanger : Config.memoryDangerMono

	title: "Memory"
	detail: root.mem ? root.mem.committedText + " of " + root.mem.poolText : ""
	detailColor: root.accentInk
	listInk: root.accentInk
	totalInk: root.mem ? root.mem.ink : root.accentInk
	panelWidth: Config.memoryTooltipWidth
	panelPadding: Config.memoryTooltipPadding
	topCount: Config.memoryTopCount
	psField: "rss"
	rowColor: (row) => row.color || root.accentInk

	function usage() {
		const m = root.mem;

		if (!m)
			return [];

		const rows = [
			{ label: "used", text: m.usedText, color: root.totalInk },
			{ label: "cached", text: m.cachedText, color: root.cachedInk },
			{ label: "buffers", text: m.buffersText, color: root.buffersInk }
		];

		if (m.swapTotal > 0)
			rows.push({ label: "swap", text: m.swapUsedText + " of " + m.swapTotalText, color: Config.memorySwap });

		rows.push({ label: "free", text: m.freeText, color: Config.foreground });

		return rows;
	}

	function segments(breadth) {
		const m = root.mem;

		if (!m || m.pool <= 0)
			return [];

		const divider = m.swapTotal > 0 ? Config.memorySeparator : 0;
		const parts = [
			{ value: m.used, color: root.totalInk },
			{ value: m.cached, color: root.cachedInk },
			{ value: m.buffers, color: root.buffersInk },
			{ value: m.ramFree, color: Config.memoryFree }
		];

		if (divider > 0) {
			parts.push({ value: 0, color: Config.memorySeparatorColor, divider: divider });
			parts.push({ value: m.swapUsed, color: Config.memorySwap });
			parts.push({ value: m.swapFree, color: Config.memoryFree });
		}

		const width = breadth - divider;
		let x = 0;

		return parts.map(function (part) {
			const share = part.divider ? part.divider : width * part.value / m.pool;
			const out = {
				x: x,
				width: share,
				color: part.color
			};

			x += out.width;
			return out;
		});
	}

	viz: [
		Item {
			id: vizBar

			width: parent.width
			height: Config.memoryVizHeight
			visible: root.mem !== null

			Repeater {
				model: root.segments(vizBar.width)

				delegate: Rectangle {
					required property var modelData

					x: modelData.x
					width: modelData.width
					height: parent.height
					color: modelData.color
				}
			}
		},

		Repeater {
			model: root.usage()

			delegate: Item {
				required property var modelData

				width: parent.width
				height: Math.max(segmentLabel.implicitHeight, segmentValue.implicitHeight)

				Text {
					id: segmentLabel

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: modelData.color
					text: modelData.label
				}

				Text {
					id: segmentValue

					anchors.right: parent.right

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: modelData.color
					text: modelData.text
				}
			}
		}
	]
}
