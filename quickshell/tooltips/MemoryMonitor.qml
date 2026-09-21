import QtQuick
import qs.ui
import qs

ProcessPanel {
	id: root

	property var mem: root.source ? root.source.memory : null

	readonly property color accentInk: Helpers.pick(Config.mono, Config.memoryBase, Config.memoryBaseMono)
	readonly property color cachedInk: Helpers.pick(Config.mono, Config.memoryCached, Config.memoryCachedMono)
	readonly property color buffersInk: Helpers.pick(Config.mono, Config.memoryBuffers, Config.memoryBuffersMono)
	readonly property color warnInk: Helpers.pick(Config.mono, Config.memoryWarn, Config.memoryWarnMono)
	readonly property color dangerInk: Helpers.pick(Config.mono, Config.memoryDanger, Config.memoryDangerMono)

	title: "Memory"
	detail: root.mem ? Helpers.sizeText(root.mem.committed) + " of " + Helpers.sizeText(root.mem.pool) : ""
	detailColor: root.accentInk
	listInk: root.accentInk
	totalInk: root.dangerColorFor(root.pct)
	panelWidth: Config.memoryTooltipWidth
	panelPadding: Config.memoryTooltipPadding
	topCount: Config.memoryTopCount
	psField: "rss"
	rowText: (value) => Helpers.sizeText(value)
	rowColor: (value) => root.dangerColorFor(root.shareOf(value))

	function dangerColorFor(load) {
		return Helpers.dangerColor(root.accentInk, root.warnInk, root.dangerInk, Config.memoryWarnAt, Config.memoryDangerAt, load);
	}

	function usage() {
		const m = root.mem;

		if (!m)
			return [];

		const rows = [
			{ label: "used", text: Helpers.sizeText(m.used), color: root.dangerColorFor(root.pct) },
			{ label: "cached", text: Helpers.sizeText(m.cached), color: root.cachedInk },
			{ label: "buffers", text: Helpers.sizeText(m.buffers), color: root.buffersInk }
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
			{ value: m.cached, color: root.cachedInk },
			{ value: m.buffers, color: root.buffersInk },
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
			const share = part.divider ? part.divider : width * part.value / m.pool;
			const out = {
				x: x,
				width: part.divider || part.value <= 0 ? share : Math.max(Config.memoryMinSegment, share),
				color: part.color
			};

			x += out.width;
			return out;
		});
	}

	function shareOf(kb) {
		if (!root.mem || root.mem.pool <= 0)
			return 0;

		return Helpers.clamp(100 * kb / root.mem.pool, 0, 100);
	}

	viz: [
		Item {
			width: parent.width
			height: Config.memoryVizHeight
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
	]
}
