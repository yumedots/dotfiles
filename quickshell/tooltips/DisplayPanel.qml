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
	readonly property var scaleIndex: root.indexOfScale()
	readonly property var refreshIndex: root.indexOfRefresh()
	readonly property var resolutionIndex: root.indexOfResolution()
	readonly property var fontIndex: root.indexOfFont()
	readonly property string scaleText: root.scaleIndex >= 0 ? Display.scaleLabel(root.scaleValues[root.scaleIndex]) : Display.scaleLabel(root.activeScale)
	readonly property string refreshText: root.active !== null && root.active.refresh > 0 ? Math.round(root.active.refresh) + " Hz" : ""
	readonly property string fontText: String(Settings.fontSize)
	readonly property var rows: Display.rowNames()
	readonly property string currentRow: root.rows.length > 0 ? root.rows[Util.clamp(root.row, 0, root.rows.length - 1)] : ""
	readonly property int resolutionRows: Math.min(root.resolutions.length, Config.displayResolutionLimit)
	readonly property real resolutionHeight: root.resolutionRows > 0 ? root.resolutionRows * (Config.displayRowHeight + Config.displayRowGap) - Config.displayRowGap : 0
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
		resView.contentY = 0;
	}
	onResolutionCursorChanged: root.scrollResolution()

	function indexOfScale() {
		for (let i = 0; i < root.scaleValues.length; i++) {
			if (Display.sameScale(root.scaleValues[i], root.activeScale))
				return i;
		}

		return -1;
	}

	function indexOfRefresh() {
		for (let i = 0; i < root.refreshes.length; i++) {
			if (Display.sameMode(root.refreshes[i], root.active))
				return i;
		}

		return -1;
	}

	function indexOfResolution() {
		if (root.active === null)
			return -1;

		for (let i = 0; i < root.resolutions.length; i++) {
			if (root.resolutions[i].width === root.active.width && root.resolutions[i].height === root.active.height)
				return i;
		}

		return -1;
	}

	function indexOfFont() {
		for (let i = 0; i < root.fontValues.length; i++) {
			if (root.fontValues[i] === Settings.fontSize)
				return i;
		}

		return -1;
	}

	function countOf(kind) {
		if (kind === "scale")
			return root.scaleValues.length;
		if (kind === "refresh")
			return root.refreshes.length;
		if (kind === "font")
			return root.fontValues.length;
		if (kind === "resolution")
			return root.resolutions.length;

		return 1;
	}

	function currentIndexOf(kind) {
		if (kind === "scale")
			return Math.max(0, root.scaleIndex);
		if (kind === "refresh")
			return Math.max(0, root.refreshIndex);
		if (kind === "font")
			return Math.max(0, root.fontIndex);
		if (kind === "resolution")
			return Math.max(0, root.resolutionIndex);

		return 0;
	}

	function focused(kind) {
		if (!root.keyboard || root.currentRow !== kind)
			return -1;

		return Util.clamp(root.step, 0, Math.max(0, root.countOf(kind) - 1));
	}

	function scrollResolution() {
		if (root.resolutionCursor < 0)
			return;

		const step = Config.displayRowHeight + Config.displayRowGap;
		const top = root.resolutionCursor * step;

		resView.contentY = Util.scrollIntoView(resView.contentY, resView.height, resView.contentHeight, top, top + Config.displayRowHeight);
	}

	function wrap(value, count) {
		return ((value % count) + count) % count;
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
			root.step = root.wrap(root.step + delta, count);

		root.keyboard = true;
	}

	function stepMonitor(delta) {
		const names = root.monitors.map(function (monitor) { return monitor.name; });

		if (names.length < 2)
			return;

		let at = names.indexOf(root.monitor === null ? "" : root.monitor.name);

		if (at < 0)
			at = 0;

		at = ((at + delta) % names.length + names.length) % names.length;
		root.step = at;
		root.output = names[at];
	}

	function activate() {
		const kind = root.currentRow;

		if (kind === "resolution") {
			root.setResolution(root.resolutions[root.step]);
			return;
		}

		if (kind === "refresh") {
			root.setMode(root.refreshes[root.step]);
			return;
		}

		if (kind === "scale") {
			root.setScale(root.scaleValues[root.step]);
			return;
		}

		if (kind === "font")
			root.setFont(root.fontValues[root.step]);
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
		property real pad: 0

		width: Config.displayPanelWidth
		height: headerLabel.implicitHeight

		Text {
			id: headerLabel

			x: header.pad
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
			model: group.model
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

		StepGroup {
			label: Config.displayScaleTitle.toUpperCase()
			kind: "scale"
			model: root.scaleValues.map(function (value) { return { value: value, label: Display.scaleLabel(value) }; })
			selected: root.scaleIndex
			shown: root.scaleText
			visible: root.ready && root.scaleValues.length > 0
			onPick: function (value) { root.setScale(value); }
		}

		StepGroup {
			label: Config.displayRefreshTitle.toUpperCase()
			kind: "refresh"
			model: root.refreshes.map(function (mode) { return { value: mode, label: Math.round(mode.refresh) + " Hz" }; })
			selected: root.refreshIndex
			shown: root.refreshText
			visible: root.ready && root.refreshes.length > 0
			onPick: function (value) { root.setMode(value); }
		}

		StepGroup {
			label: Config.displayFontTitle.toUpperCase()
			kind: "font"
			model: root.fontValues.map(function (value) { return { value: value, label: String(value) }; })
			selected: root.fontIndex
			shown: root.fontText
			visible: root.ready
			onPick: function (value) { root.setFont(value); }
		}

		Item {
			width: Config.displayPanelWidth
			height: resHead.implicitHeight + Config.displayRowGap + root.resolutionHeight
			visible: root.ready

			Column {
				id: resHead

				width: parent.width
				spacing: Config.displayRowGap

				Header {
					label: Config.displayResolutionTitle.toUpperCase()
					pad: Config.displayRowPad
				}

				Rectangle {
					width: Config.displayPanelWidth
					height: Config.displaySeparatorHeight
					color: Config.displaySeparatorColor
				}
			}

			Flickable {
				id: resView

				anchors.top: resHead.bottom
				anchors.topMargin: Config.displayRowGap
				width: Config.displayPanelWidth - Config.scrollbarWidth - Config.displayRowGap
				height: root.resolutionHeight
				contentHeight: resolved.implicitHeight
				clip: true
				interactive: false
				boundsBehavior: Flickable.StopAtBounds

				Column {
					id: resolved

					width: resView.width
					spacing: Config.displayRowGap

					Repeater {
						model: root.resolutions

						delegate: Line {
							required property var modelData
							required property int index

							readonly property var modes: root.monitor === null ? [] : Display.refreshesFor(root.monitor, modelData)

							lineWidth: resView.width
							label: modelData.label
							hint: modes.length > 0 ? Math.round(modes[0].refresh) + " Hz" : ""
							lit: root.focused("resolution") === index
							onPick: function () { root.setResolution(modelData); }
						}
					}
				}
			}

			Item {
				anchors.left: resView.left
				anchors.top: resView.top
				width: resView.width
				height: resView.height

				MouseArea {
					anchors.fill: parent
					acceptedButtons: Qt.NoButton

					onWheel: function (wheel) {
						const step = Config.displayRowHeight + Config.displayRowGap;

						resView.contentY = Util.clamp(resView.contentY + (wheel.angleDelta.y > 0 ? -step : step), 0, Math.max(0, resView.contentHeight - resView.height));
						wheel.accepted = true;
					}
				}

				Scrollbar {
					view: resView
					offset: Config.displayRowGap
				}
			}
		}

	}
}
