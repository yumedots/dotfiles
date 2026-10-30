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
	readonly property bool ready: root.monitor !== null && root.monitor !== undefined
	readonly property color ink: Config.mono ? Config.displayBaseMono : Config.displayBase
	readonly property var resolutions: root.ready ? root.monitor.resolutions : []
	readonly property int resolutionRows: Math.min(root.resolutions.length, Config.displayResolutionLimit)
	readonly property string currentRow: root.panel.cursor || ""
	readonly property int cursorStep: root.panel.step || 0
	readonly property int resolutionCursor: root.currentRow === "resolution" ? root.cursorStep : -1
	readonly property string modeText: root.ready ? root.monitor.width + "x" + root.monitor.height + " \u00b7 " + Math.round(root.monitor.refresh) + " Hz" : ""
	readonly property string title: !root.ready ? Config.displayTitle : (root.monitor.name || root.monitor.description || "")
	readonly property string detail: root.ready && root.monitor.description !== root.title ? root.monitor.description || "" : ""

	implicitWidth: Config.displayPanelWidth + Config.displayPanelPadding * 2
	implicitHeight: body.implicitHeight + Config.displayPanelPadding * 2

	focus: true

	onShownChanged: if (root.shown) resList.reset()
	onCursorStepChanged: if (root.resolutionCursor >= 0) resList.ensureVisible(root.resolutionCursor)

	Keys.onPressed: function (event) { Yudae.cmd("screen", { keyCode: event.key }) }

	function format(kind, value) {
		if (kind !== "scale" || value === "")
			return value;

		const number = Number(value);

		return isFinite(number) ? number.toFixed(2) : value;
	}

	function isCurrent(row) {
		return root.ready && row.width === root.monitor.width && row.height === root.monitor.height;
	}

	component Header: Item {
		id: header

		property string label: ""
		property string value: ""

		width: Config.displayPanelWidth
		height: Math.max(headerLabel.implicitHeight, headerValue.implicitHeight)

		Text {
			id: headerLabel

			anchors.verticalCenter: parent.verticalCenter
			font.family: Config.fontFamily
			font.pixelSize: Config.displayLabelSize
			font.letterSpacing: 1
			color: Config.muted
			text: header.label
		}

		Text {
			id: headerValue

			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			font.family: Config.fontFamily
			font.pixelSize: Config.displayLabelSize
			color: root.ink
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
			value: root.format(group.kind, steps.hoverLabel !== "" ? steps.hoverLabel : group.shown)
		}

		StepBar {
			id: steps

			width: Config.displayPanelWidth
			model: group.options
			selected: group.selected
			cursor: group.cursor
			ink: root.ink
			formatter: (value) => root.format(group.kind, value)

			onPick: function (value) { Yudae.cmd("screen", { pick: { kind: group.kind, value: value } }) }
		}
	}

	component Line: Item {
		id: line

		property string label: ""
		property string hint: ""
		property bool lit: false
		property bool current: false
		property real lineWidth: Config.displayPanelWidth
		property var onPick

		width: line.lineWidth
		height: Config.displayRowHeight

		Highlight {
			id: hl

			active: line.lit || line.current || hit.containsMouse
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
			color: hl.active ? hl.ink : Config.muted
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

			Item {
				width: parent.width
				height: Math.max(nameText.implicitHeight, refreshGlyph.implicitHeight)

				Text {
					id: nameText

					anchors.left: parent.left
					anchors.right: refreshGlyph.left
					anchors.rightMargin: Config.displayValueGap
					anchors.verticalCenter: parent.verticalCenter
					elide: Text.ElideRight
					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: Config.foreground
					text: root.title
				}

				Glyph {
					id: refreshGlyph

					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					text: Config.displayIconRefresh
					onActivate: function () { Yudae.cmd("screen", { detect: true }) }
				}
			}

			Text {
				width: parent.width
				visible: root.ready
				font.family: Config.fontFamily
				font.pixelSize: Config.displayDetailSize
				color: root.ink
				text: root.modeText
			}

			Text {
				width: parent.width
				elide: Text.ElideRight
				visible: root.detail !== ""
				font.family: Config.fontFamily
				font.pixelSize: Config.displayDetailSize
				color: Config.muted
				text: root.detail
			}

			Text {
				width: parent.width
				visible: !root.ready
				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.muted
				text: Config.displayNothing
			}
		}

		Rectangle {
			width: Config.displayPanelWidth
			height: Config.displaySeparatorHeight
			color: Config.displaySeparatorColor
			visible: root.ready
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

		Rectangle {
			width: Config.displayPanelWidth
			height: Config.displaySeparatorHeight
			color: Config.displaySeparatorColor
			visible: root.ready && root.resolutions.length > 0
		}

		Item {
			width: Config.displayPanelWidth
			height: resHead.height + Config.displayRowGap + resList.height
			visible: root.ready && root.resolutions.length > 0

			Header {
				id: resHead

				label: Config.displayResolutionTitle.toUpperCase()
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
					current: root.isCurrent(modelData)
					lit: root.resolutionCursor === index
					onPick: function () { Yudae.cmd("screen", { pick: { kind: "resolution", value: modelData.label } }) }
				}
			}
		}
	}
}
