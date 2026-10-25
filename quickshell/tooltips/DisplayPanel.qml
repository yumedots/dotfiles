import QtQuick
import Quickshell
import qs
import qs.ui
import qs.services

Item {
	id: root

	property bool shown: false
	property string output: ""
	property var monitors: Yudae.screenMonitors
	property string raw: Yudae.screenRaw

	signal closeRequested()
	signal changed()

	readonly property var panel: Yudae.screenPanel
	readonly property var groups: root.panel.groups || []
	readonly property var monitor: Yudae.screenActive
	readonly property bool ready: root.monitor !== null
	readonly property color ink: Util.pick(Config.mono, Config.displayBase, Config.displayBaseMono)
	readonly property var resolutions: root.ready ? root.monitor.resolutions : []
	readonly property int resolutionRows: Math.min(root.resolutions.length, Config.displayResolutionLimit)
	readonly property string currentRow: root.panel.cursor || ""
	readonly property int cursorStep: root.panel.step || 0
	readonly property int resolutionCursor: root.currentRow === "resolution" ? root.cursorStep : -1

	implicitWidth: Config.displayPanelWidth + Config.displayPanelPadding * 2
	implicitHeight: body.implicitHeight + Config.displayPanelPadding * 2

	focus: true

	onShownChanged: if (root.shown) resList.reset()
	onCursorStepChanged: if (root.resolutionCursor >= 0) resList.ensureVisible(root.resolutionCursor)

	Keys.onPressed: Yudae.screenKey(event.key)

	component Header: Item {
		id: header

		property string label: ""
		property string value: ""

		width: Config.displayPanelWidth
		height: headerLabel.implicitHeight

		Text {
			id: headerLabel

			anchors.verticalCenter: parent.verticalCenter
			font.family: Config.fontFamily
			font.pixelSize: Config.displayLabelSize
			font.letterSpacing: 1
			color: Config.foreground
			text: header.label
		}

		Text {
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			font.family: Config.fontFamily
			font.pixelSize: Config.displayLabelSize
			color: Config.foreground
			text: header.value
		}
	}

	component StepGroup: Column {
		id: group

		property string label: ""
		property string kind: ""
		property var options: []
		property int selected: -1
		property string shown: ""
		property int cursor: -1

		width: Config.displayPanelWidth
		spacing: Config.displayRowGap

		Header {
			label: group.label
			value: steps.hoverLabel !== "" ? steps.hoverLabel : group.shown
		}

		StepBar {
			id: steps

			width: Config.displayPanelWidth
			model: group.options
			selected: group.selected
			cursor: group.cursor
			ink: root.ink

			onPick: Yudae.screenPick(group.kind, value)
		}
	}

	component Line: Item {
		id: line

		property string label: ""
		property string hint: ""
		property bool lit: false
		property real lineWidth: Config.displayPanelWidth
		property var onPick

		width: line.lineWidth
		height: Config.displayRowHeight

		Highlight {
			id: hl

			active: line.lit || hit.containsMouse
		}

		Text {
			anchors.verticalCenter: parent.verticalCenter
			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: hl.ink
			text: line.label
		}

		Text {
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: hl.ink
			text: line.hint
		}

		MouseArea {
			id: hit

			anchors.fill: parent
			hoverEnabled: true

			onClicked: if (line.onPick) line.onPick()
		}
	}

	component Glyph: Text {
		id: glyph

		property var onActivate

		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		color: hit.containsMouse ? Config.foreground : Config.muted

		MouseArea {
			id: hit

			anchors.fill: parent
			anchors.margins: -Config.barHitPadding
			hoverEnabled: true

			onClicked: if (glyph.onActivate) glyph.onActivate()
		}
	}

	Column {
		id: body

		x: Config.displayPanelPadding
		y: Config.displayPanelPadding
		width: Config.displayPanelWidth
		spacing: Config.displayGroupGap

		Column {
			width: parent.width
			spacing: Config.displayDetailGap

			Row {
				spacing: Config.displayValueGap

				Text {
					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: Config.foreground
					text: root.ready ? root.monitor.name : Config.displayTitle
				}

				Glyph {
					text: Config.displayIconRefresh
					onActivate: Yudae.screenDetect()
				}
			}

			Text {
				width: parent.width
				elide: Text.ElideRight
				visible: root.ready && root.monitor.description !== ""
				font.family: Config.fontFamily
				font.pixelSize: Config.displayDetailSize
				color: Config.foreground
				text: root.ready ? root.monitor.description : ""
			}

			Text {
				width: parent.width
				visible: !root.ready
				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.foreground
				text: Config.displayNothing
			}
		}

		Repeater {
			model: root.groups

			delegate: StepGroup {
				required property var modelData

				label: modelData.label.toUpperCase()
				kind: modelData.kind
				options: modelData.options
				selected: modelData.selected
				shown: modelData.shown
				cursor: root.panel.keyboard === true && root.currentRow === modelData.kind ? root.cursorStep : -1
				visible: modelData.visible
			}
		}

		Item {
			width: Config.displayPanelWidth
			height: resHead.implicitHeight + Config.displayRowGap + resList.height
			visible: root.ready

			Column {
				id: resHead

				width: parent.width
				spacing: Config.displayRowGap

				Header {
					label: Config.displayResolutionTitle.toUpperCase()
				}

				Rectangle {
					width: Config.displayPanelWidth
					height: Config.displaySeparatorHeight
					color: Config.displaySeparatorColor
				}
			}

			Selector {
				id: resList

				anchors.top: resHead.bottom
				anchors.topMargin: Config.displayRowGap
				width: Config.displayPanelWidth
				visibleRows: root.resolutionRows
				rowHeight: Config.displayRowHeight
				rowSpacing: Config.displayRowGap
				model: root.resolutions

				delegate: Line {
					required property var modelData
					required property int index

					lineWidth: ListView.view.rowWidth
					label: modelData.label
					hint: modelData.maxRefresh > 0 ? modelData.maxRefresh + " Hz" : ""
					lit: root.resolutionCursor === index
					onPick: Yudae.screenPick("resolution", modelData.label)
				}
			}
		}
	}
}
