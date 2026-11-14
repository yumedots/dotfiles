import QtQuick
import qs.ui
import qs
import qs.services

Item {
	id: root

	readonly property var mix: Yudae.audio
	readonly property var nodes: root.mix.nodes || []
	readonly property bool onScreen: root.Window.window ? root.Window.window.visible : false

	property int targetIndex: 0

	signal closeRequested()

	focus: true

	property bool shown: false
	property bool compact: false
	property bool keyboard: false
	property bool shift: false
	readonly property bool showApps: (root.mix.streams || []).length > 0 && !root.compact
	readonly property var globalNode: root.nodeOf(root.mix.sink)
	readonly property var sinks: root.compact ? [] : (root.mix.sinks || [])
	readonly property var deviceRows: root.sinks.map((sink) => root.nodeOf(sink.id)).filter((node) => node !== null)
	readonly property var appRows: root.showApps ? (root.mix.streams || []).map(root.nodeOf).filter((node) => node !== null) : []
	readonly property int globalOffset: root.globalNode !== null ? 1 : 0
	readonly property var rows: root.globalNode !== null
		? [root.globalNode].concat(root.appRows).concat(root.deviceRows)
		: root.appRows.concat(root.deviceRows)

	onOnScreenChanged: Yudae.cmd("audio", { watch: { on: root.onScreen === true } })

	onShownChanged: {
		if (root.shown) {
			root.forceActiveFocus();

			return;
		}

		root.keyboard = false;
		root.shift = false;
		root.pending = { id: -1, volume: -1 };
	}

	readonly property real contentWidth: Config.mixerWidth
	readonly property var steps: Array(Config.mixerStepCount).fill(1)

	implicitWidth: root.contentWidth + Config.mixerPadding * 2
	implicitHeight: body.implicitHeight + Config.mixerPadding * 2

	readonly property var selectedNode: root.rows.length > 0
		? root.rows[Calc.clamp(root.targetIndex, 0, root.rows.length - 1)]
		: null

	function moveTarget(step) {
		const last = root.rows.length - 1;

		if (last < 0)
			return;

		root.targetIndex = Calc.clamp(root.targetIndex + step, 0, last);
	}

	function focusNode(node) {
		for (let i = 0; i < root.rows.length; i++) {
			if (node !== null && root.rows[i] === node) {
				root.targetIndex = i;

				return;
			}
		}
	}

	function nodeOf(id) {
		for (let i = 0; i < root.nodes.length; i++) {
			if (root.nodes[i].id === id)
				return root.nodes[i];
		}

		return null;
	}

	function setFader(node, fraction) {
		if (!node)
			return;

		root.focusNode(node);

		const level = Calc.clamp(fraction, 0, Config.mixerMaxVolume);

		if (!isFinite(level))
			return;

		if (node.volume !== undefined && Math.abs(root.volumeOf(node) - level) < 0.004)
			return;

		root.pending = { id: node.id, volume: level };
		settle.restart();
		Yudae.cmd("audio", { volume: { id: node.id, level: level } });
	}

	function beginDrag(node, fader, position) {
		const origin = fader.mapToItem(root, 0, 0);

		root.drag = { id: node ? node.id : -1, from: origin.x, width: fader.width, last: -1 };
	}

	function dragFader(node, fader, bar, position, modifiers) {
		if (!node || !fader || !bar || root.drag.id !== node.id || !(root.drag.width > 0))
			return;

		root.keyboard = false;

		const at = fader.mapToItem(root, position, 0).x - root.drag.from;

		if (!isFinite(at))
			return;

		if (root.drag.last >= 0 && Math.abs(at - root.drag.last) > root.drag.width / 2)
			return;

		root.drag = { id: root.drag.id, from: root.drag.from, width: root.drag.width, last: at };

		const fraction = Calc.clamp(at / root.drag.width, 0, 1);
		const shift = (modifiers & Qt.ShiftModifier) !== 0;

		root.shift = shift;
		root.setFader(node, shift ? fraction : (bar.indexAt(at, 0) + 1) / bar.count);
	}

	function nudgeVolume(step) {
		const node = root.selectedNode;

		if (!node)
			return;

		root.setFader(node, Calc.clamp(root.volumeOf(node) + step, 0, Config.mixerMaxVolume));
	}

	Keys.onPressed: function (event) {
		if (event.key === Qt.Key_Shift)
			root.shift = true;

		if (Input.direction(event) !== "")
			root.keyboard = true;

		Input.mixer(event, root);
	}

	Keys.onReleased: function (event) {
		if (event.key === Qt.Key_Shift)
			root.shift = false;
	}

	function toggleMute(node) {
		if (!node)
			return;

		Yudae.cmd("audio", { mute: { id: node.id, muted: node.muted !== true } });
	}

	function iconFor(node) {
		if (!node)
			return "";

		return AppIcons.iconOf(node.appId, node.appIds);
	}

	function makeDefault(node) {
		if (!node)
			return;

		Yudae.cmd("audio", { default: { id: node.id } });
	}

	function activateNode(node) {
		if (!node || !node.isSink)
			return;

		root.makeDefault(node);
	}

	property var drag: ({ id: -1, from: 0, width: 0, last: -1 })
	property var pending: ({ id: -1, volume: -1 })

	onMixChanged: root.reconcile()

	Timer {
		id: settle

		interval: Config.mixerPendingMs
		onTriggered: root.pending = { id: -1, volume: -1 }
	}

	function volumeOf(node) {
		if (!node)
			return 0;

		if (root.pending.id === node.id)
			return root.pending.volume;

		return node.volume;
	}

	function reconcile() {
		if (root.pending.id < 0)
			return;

		const node = root.nodeOf(root.pending.id);

		if (!node || Math.abs(node.volume - root.pending.volume) < 0.004)
			root.pending = { id: -1, volume: -1 };
	}

	component MixRow: Item {
		id: row

		property var node
		property int rowIndex: -1
		property bool global: false

		readonly property bool stream: !!row.node && row.node.isStream === true
		readonly property bool muted: !!row.node && row.node.muted === true
		readonly property bool selected: row.rowIndex === root.targetIndex
		readonly property real volume: root.volumeOf(row.node)
		readonly property string iconSource: row.stream ? root.iconFor(row.node) : ""
		readonly property string glyph: row.stream ? Config.iconApp : Config.iconVolumeHigh
		readonly property real level: Calc.clamp(row.volume / Config.mixerMaxVolume, 0, 1)
		readonly property int step: Math.round(row.level * Config.mixerStepCount) - 1
		readonly property real hoverPad: Math.max(0, (row.height - Config.mixerFaderThickness) / 2)

		height: Math.max(Config.mixerDeviceIconSize, Settings.fontSize)
		implicitHeight: height

		HoverHandler {
			id: hover
		}

		Highlight {
			id: hl

			active: (row.selected && root.keyboard) || hover.hovered
		}

		MouseArea {
			anchors.fill: parent

			onClicked: {
				root.keyboard = false;
				root.targetIndex = row.rowIndex;
				root.activateNode(row.node);
			}
		}

		Item {
			id: iconSlot

			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			width: Config.mixerDeviceIconSize
			height: Math.min(Config.mixerDeviceIconSize, row.height)

			AppIcon {
				anchors.centerIn: parent
				implicitSize: Config.mixerIconSize
				visible: row.iconSource !== ""
				opacity: row.muted ? 0.45 : 1
				source: row.iconSource
			}

			Glyph {
				anchors.fill: parent
				visible: row.iconSource === ""
				size: Config.mixerIconSize
				color: row.muted ? Config.muted : Config.foreground
				glyph: row.glyph
			}
		}

		Item {
			id: fader

			anchors.left: iconSlot.right
			anchors.leftMargin: Config.mixerListGap
			anchors.right: parent.right
			anchors.rightMargin: Config.mixerListGap
			anchors.verticalCenter: parent.verticalCenter
			height: parent.height

			StepBar {
				id: faderBar

				anchors.verticalCenter: parent.verticalCenter
				anchors.left: parent.left
				anchors.right: parent.right
				height: Config.mixerFaderThickness
				model: root.steps
				follow: false
				hitPad: row.hoverPad
				selected: row.step
				level: root.shift ? row.level : -1
				lens: false
				ink: row.muted && !hl.active ? Config.dim : hl.ink
			}

			MouseArea {
				anchors.fill: parent
				preventStealing: true

				onPressed: mouse => {
					root.beginDrag(row.node, fader, mouse.x);
					root.dragFader(row.node, fader, faderBar, mouse.x, mouse.modifiers);
				}
				onPositionChanged: mouse => root.dragFader(row.node, fader, faderBar, mouse.x, mouse.modifiers)
			}
		}
	}

	Column {
		id: body

		anchors.left: parent.left
		anchors.top: parent.top
		anchors.margins: Config.mixerPadding
		width: root.contentWidth
		spacing: Config.mixerChannelGap

		MixRow {
			width: parent.width
			node: root.globalNode
			rowIndex: 0
			global: true
			visible: root.globalNode !== null
		}

		Repeater {
			model: root.appRows

			delegate: MixRow {
				required property var modelData
				required property int index

				width: parent.width
				node: modelData
				rowIndex: root.globalOffset + index
			}
		}

		Rectangle {
			width: body.width
			height: Config.mixerSeparator
			color: Config.mixerSeparatorColor
			visible: root.deviceRows.length > 0 && root.appRows.length > 0
		}

		Repeater {
			model: root.deviceRows

			delegate: GlyphRow {
				id: device

				required property var modelData
				required property int index

				readonly property int rowIndex: root.globalOffset + root.appRows.length + device.index

				width: parent.width
				glyph: Config.iconOutput
				label: device.modelData.description || device.modelData.name || ""
				current: device.modelData.isDefault === true
				dim: device.modelData.muted === true
				selected: device.rowIndex === root.targetIndex && root.keyboard

				onActivated: {
					root.keyboard = false;
					root.targetIndex = device.rowIndex;
					root.activateNode(device.modelData);
				}
			}
		}
	}
}
