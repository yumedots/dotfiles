import QtQuick
import Quickshell
import qs
import qs.services

Item {
	id: panel

	property var source: null
	property string title: ""
	property string detail: ""
	property color detailColor: Config.foreground
	property color listInk: Config.foreground
	property color totalInk: Config.foreground
	property real panelWidth: Config.cpuTooltipWidth
	property real panelPadding: Config.cpuTooltipPadding
	property int topCount: Config.cpuTopCount
	property string psField: "pcpu"
	property var rowText: (value) => String(value)
	property var rowColor: (value) => Config.foreground
	property alias viz: vizColumn.data

	property var allProcs: []
	property var heldProcs: []
	property string filter: ""

	readonly property bool searching: searchField.typing
	readonly property bool filtering: panel.searching || panel.filter !== ""
	readonly property var procs: panel.filtering ? System.filterProcesses(panel.allProcs, Config.psIgnore, panel.filter) : (panel.heldProcs.length > 0 ? panel.heldProcs : System.topProcesses(panel.allProcs, Config.psIgnore))
	readonly property bool showList: panel.procs.length > 0 || panel.filtering
	readonly property real pct: panel.source ? panel.source.pct : 0
	readonly property bool onScreen: panel.Window.window ? panel.Window.window.visible : false

	focus: true

	signal closeRequested()

	implicitWidth: panel.panelWidth + panel.panelPadding * 2
	implicitHeight: column.implicitHeight + panel.panelPadding * 2

	onOnScreenChanged: {
		if (!panel.onScreen) {
			searchField.clear();
			searchField.typing = false;
			panel.filter = "";
			return;
		}

		panel.heldProcs = System.topProcesses(panel.allProcs, Config.psIgnore);
		procList.currentIndex = -1;

		if (panel.source && panel.source.refresh)
			panel.source.refresh();
	}

	onSearchingChanged: {
		if (!panel.searching)
			panel.forceActiveFocus();
	}

	Component.onCompleted: topProcesses.reload()

	Keys.onPressed: function (event) {
		if (panel.searching)
			return;

		if (Input.hint(event)) {
			searchField.startTyping();
			event.accepted = true;
		} else if (Input.cancel(event)) {
			panel.closeRequested();
			event.accepted = true;
		} else {
			procList.handleKey(event);
		}
	}

	Request {
		id: topProcesses

		command: ["ps", "-eo", panel.psField + "=,pid=,comm:16=,args=", "--sort=-" + panel.psField]

		function reload() {
			if (!topProcesses.running)
				topProcesses.running = true;
		}

		onDone: function (text) {
			panel.allProcs = System.parseTopProcesses(text);
			panel.heldProcs = System.holdProcessOrder(panel.heldProcs, System.topProcesses(panel.allProcs, Config.psIgnore));
		}
	}

	Timer {
		interval: Config.cpuPollMs * 2
		running: panel.onScreen
		repeat: true
		triggeredOnStart: true
		onTriggered: topProcesses.reload()
	}

	Column {
		id: column

		x: panel.panelPadding
		y: panel.panelPadding
		width: panel.panelWidth
		spacing: 6

		Item {
			width: column.width
			height: Math.max(titleText.implicitHeight, totalText.implicitHeight)

			Text {
				id: titleText

				width: parent.width - totalText.width - 8
				elide: Text.ElideRight

				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
				color: Config.foreground
				text: panel.title
			}

			Text {
				id: totalText

				anchors.right: parent.right

				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
				color: panel.totalInk
				text: Math.round(panel.pct) + "%"
			}
		}

		Text {
			width: column.width
			elide: Text.ElideRight
			visible: text !== ""

			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: panel.detailColor
			text: panel.detail
		}

		Item {
			id: vizSlot

			width: column.width
			height: vizColumn.implicitHeight

			Column {
				id: vizColumn

				width: parent.width
				spacing: 6
			}
		}

		Rectangle {
			id: headerBox

			width: column.width
			height: searchField.implicitHeight
			visible: panel.showList
			color: Config.launcherSearchBox

			Text {
				id: listTitle

				anchors.left: parent.left
				anchors.leftMargin: Config.procSearchPadding
				anchors.verticalCenter: parent.verticalCenter

				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
				color: panel.listInk
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

				onEdited: panel.filter = searchField.text
			}
		}

		ProcessList {
			id: procList

			width: column.width
			visibleRows: panel.topCount
			visible: panel.showList
			model: panel.procs

			onKillRequested: function (proc) {
				Quickshell.execDetached(System.killCommand(proc.pid, Config.procKillSignal));
			}

			delegate: Item {
				id: row

				required property var modelData
				required property int index

				readonly property bool active: procList.currentIndex === row.index

				width: ListView.view.rowWidth
				height: ListView.view.rowHeight

				Highlight {
					id: hl

					active: row.active
				}

				Text {
					id: process

					width: parent.width - amount.width - 8
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: hl.ink
					text: modelData.name
				}

				Text {
					id: amount

					anchors.right: parent.right

					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: panel.rowColor(modelData.value)
					text: panel.rowText(modelData.value)
				}

				MouseArea {
					anchors.fill: parent

					onClicked: {
						if (row.active)
							procList.killRequested(row.modelData);
						else
							procList.currentIndex = row.index;
					}
				}
			}
		}
	}
}
