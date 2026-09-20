import QtQuick
import Quickshell
import Quickshell.Io
import qs.ui
import qs

Item {
	id: root

	property var source: null
	property var info: ({ model: "", cores: 0, threads: 0, mhz: 0, cache: 0 })
	property var allProcs: []
	property var heldProcs: []
	property string filter: ""

	readonly property bool searching: searchField.typing
	readonly property bool filtering: root.searching || root.filter !== ""
	readonly property var procs: root.filtering ? Helpers.filterProcesses(root.allProcs, Config.psIgnore, root.filter) : (root.heldProcs.length > 0 ? root.heldProcs : Helpers.topProcesses(root.allProcs, Config.psIgnore))
	readonly property bool showList: root.procs.length > 0 || root.filtering

	focus: true

	signal closeRequested()

	readonly property real pct: root.source ? root.source.pct : 0
	readonly property var cores: root.source && root.source.cores ? root.source.cores : []

	readonly property bool onScreen: root.Window.window ? root.Window.window.visible : false
	readonly property real blockSize: (Config.cpuTooltipWidth - (Config.cpuBlockColumns - 1) * Config.cpuBlockGap) / Config.cpuBlockColumns
	readonly property int blockRows: Math.max(1, Math.ceil(root.cores.length / Config.cpuBlockColumns))
	readonly property string spec: Helpers.cpuSpecLine(root.info)
	readonly property real vizHeight: root.blockRows * (root.blockSize + Config.cpuBlockGap) - Config.cpuBlockGap

	implicitWidth: Config.cpuTooltipWidth + Config.cpuTooltipPadding * 2
	implicitHeight: column.implicitHeight + Config.cpuTooltipPadding * 2

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

	Component.onCompleted: topProcesses.reload()

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
	}		onSearchingChanged: {
			if (!root.searching)
				root.forceActiveFocus();
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

		command: ["ps", "-eo", "pcpu=,pid=,comm=", "--sort=-pcpu"]

		function reload() {
			if (!topProcesses.running)
				topProcesses.running = true;
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
			id: visualizer

			width: column.width
			height: root.vizHeight

			CellGrid {
				id: coreGrid

				values: root.cores
				columns: Config.cpuBlockColumns
				cellSize: root.blockSize
				gap: Config.cpuBlockGap
				colorFor: function (value) { return root.blockColor(value); }
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
				color: Config.cpuBase
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
			visibleRows: Config.cpuTopCount
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

					width: parent.width - percent.width - 8
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: row.active ? Config.launcherHighlightText : Config.foreground
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
