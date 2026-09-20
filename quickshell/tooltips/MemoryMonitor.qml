import QtQuick
import Quickshell
import Quickshell.Io
import qs.ui
import qs

Item {
	id: root

	property var source: null
	property var allProcs: []
	property var heldProcs: []
	property string filter: ""

	readonly property bool searching: searchField.typing
	readonly property color accentInk: Helpers.pick(Config.mono, Config.memoryBase, Config.memoryBaseMono)
	readonly property color cachedInk: Helpers.pick(Config.mono, Config.memoryCached, Config.memoryCachedMono)
	readonly property color buffersInk: Helpers.pick(Config.mono, Config.memoryBuffers, Config.memoryBuffersMono)
	readonly property color warnInk: Helpers.pick(Config.mono, Config.memoryWarn, Config.memoryWarnMono)
	readonly property color dangerInk: Helpers.pick(Config.mono, Config.memoryDanger, Config.memoryDangerMono)
	readonly property bool filtering: root.searching || root.filter !== ""
	readonly property var procs: root.filtering ? Helpers.filterProcesses(root.allProcs, Config.psIgnore, root.filter) : (root.heldProcs.length > 0 ? root.heldProcs : Helpers.topProcesses(root.allProcs, Config.psIgnore))
	readonly property bool showList: root.procs.length > 0 || root.filtering

	focus: true

	signal closeRequested()

	readonly property var mem: root.source ? root.source.memory : null
	readonly property real pct: root.mem ? root.mem.pct : 0

	readonly property bool onScreen: root.Window.window ? root.Window.window.visible : false

	implicitWidth: Config.memoryTooltipWidth + Config.memoryTooltipPadding * 2
	implicitHeight: column.implicitHeight + Config.memoryTooltipPadding * 2

	onOnScreenChanged: {
		if (!root.onScreen) {
			searchField.clear();
			searchField.typing = false;
			root.filter = "";
			return;
		}

		root.heldProcs = Helpers.topProcesses(root.allProcs, Config.psIgnore);
		procList.currentIndex = -1;

		if (root.source && root.source.refresh)
			root.source.refresh();
	}

	Component.onCompleted: ramProcesses.reload()

	Keys.onPressed: function (event) {
		if (root.searching)
			return;

		if (event.text === Config.procHintKey) {
			searchField.startTyping();
			event.accepted = true;
		} else if (event.key === Qt.Key_Escape) {
			root.closeRequested();
			event.accepted = true;
		} else {
			procList.handleKey(event);
		}
	}

	onSearchingChanged: {
		if (!root.searching)
			root.forceActiveFocus();
	}

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

		return Math.max(0, Math.min(100, 100 * kb / root.mem.pool));
	}

	Process {
		id: ramProcesses

		command: ["ps", "-eo", "rss=,pid=,comm:16=,args=", "--sort=-rss"]

		function reload() {
			if (!ramProcesses.running)
				ramProcesses.running = true;
		}

		stdout: StdioCollector {
			onStreamFinished: {
				root.allProcs = Helpers.parseTopProcesses(text);
				root.heldProcs = Helpers.holdProcessOrder(root.heldProcs, Helpers.topProcesses(root.allProcs, Config.psIgnore));
			}
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
			color: root.accentInk
			text: root.mem ? Helpers.sizeText(root.mem.committed) + " of " + Helpers.sizeText(root.mem.pool) : ""
		}

		Item {
			id: visualizer

			width: column.width
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
			id: headerBox

			width: column.width
			height: searchField.implicitHeight
			visible: root.showList
			color: Config.launcherSearchBox

			Text {
				id: listTitle

				anchors.left: parent.left
				anchors.leftMargin: Config.procSearchPadding
				anchors.verticalCenter: parent.verticalCenter

				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
				color: root.accentInk
				text: Config.topProcessTitle
			}

			SearchField {
				id: searchField

				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				boxColor: "transparent"
				size: Config.fontSize
				hintKey: Config.procSearchHint
				width: searchField.implicitWidth

				onEdited: root.filter = searchField.text
			}
		}

		ProcessList {
			id: procList

			width: column.width
			visibleRows: Config.memoryTopCount
			visible: root.showList
			model: root.procs

			onKillRequested: function (proc) {
				Quickshell.execDetached(Helpers.killCommand(proc.pid, Config.procKillSignal));
			}

			delegate: Item {
				id: row

				required property var modelData
				required property int index

				readonly property bool active: procList.currentIndex === row.index

				width: ListView.view.rowWidth
				height: ListView.view.rowHeight

				Text {
					id: process

					width: parent.width - amount.width - 8
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: row.active ? Config.launcherHighlightText : Config.foreground
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
