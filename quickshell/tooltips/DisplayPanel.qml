import QtQuick
import Quickshell
import qs
import qs.ui

Item {
	id: root

	property bool shown: false
	property string output: ""
	property var monitors: []
	property string raw: ""

	signal closeRequested()
	signal changed()

	readonly property var state: Settings.state
	readonly property var monitor: Display.findMonitor(root.monitors, root.output)
	readonly property bool ready: root.monitor !== null
	readonly property color ink: Util.pick(Config.mono, Config.displayBase, Config.displayBaseMono)
	readonly property var active: root.ready
		? Display.parseMode(Display.modeText({ width: root.monitor.width, height: root.monitor.height, refresh: root.monitor.refresh }))
		: null
	readonly property real activeScale: root.ready ? root.monitor.scale : 1
	readonly property var resolutions: Display.resolutionsOf(root.monitor)
	readonly property var refreshes: Display.refreshesFor(root.monitor, root.active).slice().sort(function (left, right) { return left.refresh - right.refresh; })
	readonly property var scaleValues: Display.scaleSteps(root.monitor, Config.displayScaleMin, Config.displayScaleMax)
	readonly property var fontValues: Config.displayFonts
	readonly property var scaleIndex: root.indexOf(root.scaleValues, function (value) { return Display.sameScale(value, root.activeScale); })
	readonly property var refreshIndex: root.indexOf(root.refreshes, function (mode) { return Display.sameMode(mode, root.active); })
	readonly property var resolutionIndex: root.indexOf(root.resolutions, function (size) { return root.active !== null && size.width === root.active.width && size.height === root.active.height; })
	readonly property var fontIndex: root.indexOf(root.fontValues, function (size) { return size === Settings.fontSize; })
	readonly property var groups: [
		{ label: Config.displayScaleTitle, kind: "scale", model: root.scaleValues, form: Display.scaleLabel, selected: root.scaleIndex, shown: root.scaleText, visible: root.ready && root.scaleValues.length > 0, pick: root.setScale },
		{ label: Config.displayRefreshTitle, kind: "refresh", model: root.refreshes, form: function (mode) { return Math.round(mode.refresh) + " Hz"; }, selected: root.refreshIndex, shown: root.refreshText, visible: root.ready && root.refreshes.length > 0, pick: root.setMode },
		{ label: Config.displayFontTitle, kind: "font", model: root.fontValues, form: String, selected: root.fontIndex, shown: root.fontText, visible: root.ready, pick: root.setFont }
	]
	readonly property var values: ({ scale: root.scaleValues, refresh: root.refreshes, font: root.fontValues, resolution: root.resolutions })
	readonly property var indexes: ({ scale: root.scaleIndex, refresh: root.refreshIndex, font: root.fontIndex, resolution: root.resolutionIndex })
	readonly property string scaleText: root.scaleIndex >= 0 ? Display.scaleLabel(root.scaleValues[root.scaleIndex]) : Display.scaleLabel(root.activeScale)
	readonly property string refreshText: Display.refreshLabel(root.active)
	readonly property string fontText: String(Settings.fontSize)
	readonly property var rows: Display.rowNames()
	readonly property string currentRow: root.rows.length > 0 ? root.rows[Util.clamp(root.row, 0, root.rows.length - 1)] : ""
	readonly property int resolutionRows: Math.min(root.resolutions.length, Config.displayResolutionLimit)
	readonly property int resolutionCursor: root.focused("resolution")

	property int row: 0
	property int step: 0
	property bool keyboard: false

	implicitWidth: Config.displayPanelWidth + Config.displayPanelPadding * 2
	implicitHeight: body.implicitHeight + Config.displayPanelPadding * 2

	focus: true

	onShownChanged: {
		root.keyboard = false;

		if (!root.shown)
			return;

		root.row = 0;
		root.step = 0;
		resList.reset();
	}
	onResolutionCursorChanged: resList.ensureVisible(root.resolutionCursor)

	function indexOf(list, match) {
		for (let i = 0; i < list.length; i++) {
			if (match(list[i]))
				return i;
		}

		return -1;
	}

	function countOf(kind) {
		return (root.values[kind] || []).length;
	}

	function currentIndexOf(kind) {
		return Math.max(0, root.indexes[kind]);
	}

	function focused(kind) {
		if (!root.keyboard || root.currentRow !== kind)
			return -1;

		return Util.clamp(root.step, 0, Math.max(0, root.countOf(kind) - 1));
	}

	function moveRow(delta) {
		const next = Display.moveCursor(root.rows, root.resolutions.length, root.row, root.step, root.keyboard ? delta : 0);

		root.keyboard = true;
		root.row = next.row;
		root.step = next.step < 0 ? root.currentIndexOf(root.currentRow) : next.step;
	}

	function moveStep(delta) {
		const count = root.countOf(root.currentRow);

		if (count <= 0)
			return;

		if (root.keyboard)
			root.step = Util.wrap(root.step, delta, count);

		root.keyboard = true;
	}

	function stepMonitor(delta) {
		const names = root.monitors.map(function (monitor) { return monitor.name; });

		if (names.length < 2)
			return;

		let at = names.indexOf(root.monitor === null ? "" : root.monitor.name);

		if (at < 0)
			at = 0;

		at = Util.wrap(at, delta, names.length);
		root.step = at;
		root.output = names[at];
	}

	function activate() {
		const kind = root.currentRow;
		const value = root.values[kind][root.step];

		if (kind === "resolution")
			root.setResolution(value);
		else if (kind === "refresh")
			root.setMode(value);
		else if (kind === "scale")
			root.setScale(value);
		else if (kind === "font")
			root.setFont(value);
	}

	function save(next, reload) {
		Settings.save(next);
		root.changed();

		if (reload)
			Quickshell.execDetached(["hyprctl", "reload"]);
	}

	function setMode(mode) {
		if (!root.ready || mode === null || mode === undefined)
			return;

		root.save(Display.setOutput(root.state, root.monitor.name, { mode: Display.modeText(mode) }), true);
	}

	function setResolution(size) {
		const list = Display.refreshesFor(root.monitor, size);

		if (list.length > 0)
			root.setMode(list[0]);
	}

	function setScale(scale) {
		if (!root.ready)
			return;

		root.save(Display.setOutput(root.state, root.monitor.name, { scale: Display.cleanScale(root.monitor, scale) }), true);
	}

	function setFont(size) {
		root.save(Display.setFontSize(root.state, size), false);
	}

	function detect() {
		if (root.raw === "")
			return;

		root.save(Display.detect(root.raw, Settings.fontSize, Settings.iconSize), true);
	}

	Keys.onPressed: function (event) {
		Input.display(event, root);
	}

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
		property var model: []
		property var form
		property int selected: -1
		property string shown: ""
		property var onPick

		width: Config.displayPanelWidth
		spacing: Config.displayRowGap

		Header {
			label: group.label
			value: steps.hoverLabel !== "" ? steps.hoverLabel : group.shown
		}

		StepBar {
			id: steps

			width: Config.displayPanelWidth
			model: group.model.map(function (value) { return { value: value, label: group.form(value) }; })
			selected: group.selected
			cursor: root.focused(group.kind)
			ink: root.ink

			onPick: function (value) {
				if (group.onPick)
					group.onPick(value);
			}
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
			id: lineLabel

			x: Config.displayRowPad
			anchors.verticalCenter: parent.verticalCenter
			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: hl.ink
			text: line.label
		}

		Text {
			anchors.right: parent.right
			anchors.rightMargin: Config.displayRowPad
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

			onClicked: if (line.onPick) line.onPick();
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

			onClicked: if (glyph.onActivate) glyph.onActivate();
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
					onActivate: function () { root.detect(); }
				}

				Glyph {
					visible: root.monitors.length > 1
					text: Config.iconPrev
					onActivate: function () { root.stepMonitor(-1); }
				}

				Glyph {
					visible: root.monitors.length > 1
					text: Config.iconNext
					onActivate: function () { root.stepMonitor(1); }
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
				model: modelData.model
				form: modelData.form
				selected: modelData.selected
				shown: modelData.shown
				visible: modelData.visible
				onPick: modelData.pick
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

					readonly property var modes: root.monitor === null ? [] : Display.refreshesFor(root.monitor, modelData)

					lineWidth: ListView.view.rowWidth
					label: modelData.label
					hint: modes.length > 0 ? Math.round(modes[0].refresh) + " Hz" : ""
					lit: root.focused("resolution") === index
					onPick: function () { root.setResolution(modelData); }
				}
			}
		}

	}
}
