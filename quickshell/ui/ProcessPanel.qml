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
	property bool showTotal: true
	property string totalOverride: ""
	property real panelWidth: Config.cpuTooltipWidth
	property real panelPadding: Config.cpuTooltipPadding
	property int topCount: Config.cpuTopCount
	property string psField: "pcpu"
	property var rowColor: (row) => row.color || Config.foreground
	property bool showProcessList: true
	property alias viz: vizColumn.data

	property string filter: ""

	readonly property bool searching: searchField.typing
	readonly property bool filtering: panel.searching || panel.filter !== ""
	readonly property var procs: (Yudae.system.panel && Yudae.system.panel.rows) || []
	readonly property bool showList: panel.showProcessList && (panel.procs.length > 0 || panel.filtering)
	readonly property real pct: panel.source ? panel.source.pct : 0
	readonly property bool onScreen: panel.Window.window ? panel.Window.window.visible : false
	property var keyAction: null

	focus: true

	signal closeRequested()

	implicitWidth: panel.panelWidth + panel.panelPadding * 2
	implicitHeight: column.implicitHeight + panel.panelPadding * 2

	onOnScreenChanged: {
		Yudae.systemCommand({ panel: { field: panel.psField, query: panel.filter } });

		if (!panel.onScreen) {
			searchField.clear();
			searchField.typing = false;
			panel.filter = "";
			return;
		}

		procList.currentIndex = -1;

		if (panel.source && panel.source.refresh)
			panel.source.refresh();
	}

	onFilterChanged: Yudae.systemCommand({ panel: { field: panel.psField, query: panel.filter } })

	onSearchingChanged: {
		if (!panel.searching)
			panel.forceActiveFocus();
	}

	Keys.onPressed: function (event) {
		if (panel.searching)
			return;

		if (Input.hint(event)) {
			searchField.startTyping();
			event.accepted = true;
		} else if (Input.cancel(event)) {
			panel.closeRequested();
			event.accepted = true;
		} else if (panel.keyAction !== null && panel.keyAction(event)) {
			return;
		} else {
			procList.handleKey(event);
		}
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
				font.pixelSize: Settings.fontSize
				color: Config.foreground
				text: panel.title
			}

			Text {
				id: totalText

				anchors.right: parent.right
				visible: panel.showTotal

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: panel.totalInk
				text: panel.totalOverride !== "" ? panel.totalOverride : Math.round(panel.pct) + "%"
			}
		}

		Text {
			width: column.width
			elide: Text.ElideRight
			visible: text !== ""

			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
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
				font.pixelSize: Settings.fontSize
				color: panel.listInk
				text: Config.topProcessTitle
			}

			SearchField {
				id: searchField

				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				boxColor: "transparent"
				size: Settings.fontSize
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
				Quickshell.execDetached(["kill", Config.procKillSignal, String(proc.pid)]);
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
					font.pixelSize: Settings.fontSize
					color: hl.ink
					text: modelData.name
				}

				Text {
					id: amount

					anchors.right: parent.right

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: panel.rowColor(modelData)
					text: modelData.valueText
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
