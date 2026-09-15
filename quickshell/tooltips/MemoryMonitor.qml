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
	property bool searching: false
	property string filter: ""

	readonly property var procs: root.searching || root.filter !== "" ? Helpers.filterProcesses(root.allProcs, Config.psIgnore, root.filter) : (root.heldProcs.length > 0 ? root.heldProcs : Helpers.topProcesses(root.allProcs, Config.psIgnore))
	readonly property bool showList: root.procs.length > 0 || root.searching

	focus: true

	signal closeRequested()

	readonly property var mem: root.source ? root.source.memory : null
	readonly property real pct: root.mem ? root.mem.pct : 0

	readonly property bool onScreen: root.Window.window ? root.Window.window.visible : false

	implicitWidth: Config.memoryTooltipWidth + Config.memoryTooltipPadding * 2
	implicitHeight: column.implicitHeight + Config.memoryTooltipPadding * 2

	onOnScreenChanged: {
		if (!root.onScreen)
			return;

		root.heldProcs = Helpers.topProcesses(root.allProcs, Config.psIgnore);

		if (root.source && root.source.refresh)
			root.source.refresh();
	}

	Component.onCompleted: ramProcesses.reload()

	Keys.onPressed: function (event) {
		if (root.searching)
			return;

		if (event.text === Config.procHintKey) {
			root.searching = true;
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

		command: ["ps", "-eo", "rss=,pid=,comm=", "--sort=-rss"]

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
				color: Config.memoryBase
				text: Config.topProcessTitle
			}

			SearchField {
				id: searchField

				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				boxColor: "transparent"
				size: Config.fontSize
				keyLabel: Config.procSearchHint
				placeholder: Config.procSearchHint
				active: root.searching
				width: searchField.implicitWidth

				onEdited: root.filter = searchField.text
				onNavigate: function (step) { procList.move(step); }
				onKeyPressed: function (event) {
					if (event.text === Config.procKillKey)
						procList.handleKey(event);
				}
				onCanceled: {
					root.searching = false;
					root.filter = "";
					searchField.clear();
				}
			}
		}

		ProcessList {
			id: procList

			width: column.width
			visibleRows: Config.memoryTopCount
			visible: root.showList && root.procs.length > 0
			model: root.procs

			onKillRequested: function (proc) {
				Quickshell.execDetached(Helpers.killCommand(proc.pid, Config.procKillSignal));
			}

			delegate: Item {
				id: row

				required property var modelData
				required property int index

				readonly property bool active: procList.currentIndex === row.index
				readonly property real fade: {
					const view = ListView.view;

					if (!view || view.height <= row.height)
						return 0;

					return Math.max(0, Math.min(1, (row.y - view.contentY) / (view.height - row.height)));
				}
				readonly property real keep: row.active || row.fade <= 0 ? 1 : 1 - row.fade * Config.procFadeOpacity

				width: ListView.view.rowWidth
				height: ListView.view.rowHeight

				Text {
					id: process

					width: parent.width - amount.width - 8
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: row.active ? Config.launcherHighlightText : Helpers.mixColors(Config.foreground, Config.memoryBase, row.fade * Config.procFade)
					opacity: row.keep
					text: modelData.name
				}

				Text {
					id: amount

					anchors.right: parent.right

					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: root.dangerColorFor(root.shareOf(modelData.value))
					opacity: row.keep
					text: Helpers.sizeText(modelData.value)
				}
			}
		}

		Text {
			width: column.width
			height: procList.implicitHeight
			visible: root.showList && root.procs.length === 0
			horizontalAlignment: Text.AlignHCenter
			verticalAlignment: Text.AlignVCenter

			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: Config.muted
			text: Config.procNoMatch
		}

	}
}
