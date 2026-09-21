import QtQuick
import qs.ui
import qs

ProcessPanel {
	id: root

	property var mem: root.source ? root.source.memory : null

	readonly property color accentInk: Util.pick(Config.mono, Config.memoryBase, Config.memoryBaseMono)
	readonly property color cachedInk: Util.pick(Config.mono, Config.memoryCached, Config.memoryCachedMono)
	readonly property color buffersInk: Util.pick(Config.mono, Config.memoryBuffers, Config.memoryBuffersMono)
	readonly property color warnInk: Util.pick(Config.mono, Config.memoryWarn, Config.memoryWarnMono)
	readonly property color dangerInk: Util.pick(Config.mono, Config.memoryDanger, Config.memoryDangerMono)

	title: "Memory"
	detail: root.mem ? System.sizeText(root.mem.committed) + " of " + System.sizeText(root.mem.pool) : ""
	detailColor: root.accentInk
	listInk: root.accentInk
	totalInk: root.dangerColorFor(root.pct)
	panelWidth: Config.memoryTooltipWidth
	panelPadding: Config.memoryTooltipPadding
	topCount: Config.memoryTopCount
	psField: "rss"
	rowText: (value) => System.sizeText(value)
	rowColor: (value) => root.dangerColorFor(root.shareOf(value))

	function dangerColorFor(load) {
		return Color.dangerColor(root.accentInk, root.warnInk, root.dangerInk, Config.memoryWarnAt, Config.memoryDangerAt, load);
	}

	function usage() {
		const m = root.mem;

		if (!m)
			return [];

		const rows = [
			{ label: "used", text: System.sizeText(m.used), color: root.dangerColorFor(root.pct) },
			{ label: "cached", text: System.sizeText(m.cached), color: root.cachedInk },
			{ label: "buffers", text: System.sizeText(m.buffers), color: root.buffersInk }
		];

		if (m.swapTotal > 0)
			rows.push({ label: "swap", text: System.sizeText(m.swapUsed) + " of " + System.sizeText(m.swapTotal), color: Config.memorySwap });

		rows.push({ label: "free", text: System.sizeText(m.free), color: Config.foreground });

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

		return Util.clamp(100 * kb / root.mem.pool, 0, 100);
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
