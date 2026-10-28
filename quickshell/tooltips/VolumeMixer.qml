import QtQuick
import qs.ui
import qs
import qs.services

Item {
	id: root

	readonly property var mix: Yudae.audio
	readonly property var nodes: root.mix.nodes || []
	readonly property var sink: root.nodeOf(root.mix.sink)
	readonly property var source: root.nodeOf(root.mix.source)
	readonly property bool onScreen: root.Window.window ? root.Window.window.visible : false
	readonly property bool hasInput: root.mix.hasInput === true
	readonly property bool recording: root.mix.recording === true

	property string picker: ""
	property int targetIndex: 0
	property int pickerIndex: 0

	signal closeRequested()

	focus: true

	property bool shown: false
	property bool compact: false
	readonly property bool showApps: root.hasApps && !root.compact

	onOnScreenChanged: Yudae.audioWatch(root.onScreen)

	onShownChanged: if (!root.shown) {
		root.keyboard = false;
		root.shift = false;
	}

	Timer {
		id: nodeRefreshTimer

		interval: 1000
		onTriggered: root.pruneHolds()
	}

	onNodesChanged: nodeRefreshTimer.restart()

	readonly property real contentWidth: Config.mixerWidth
	readonly property var devices: root.picker === "" ? [] : root.sortedDevices(root.picker === "input")
	readonly property bool hasApps: root.nodes.some(function (node) { return root.streamVisible(node); })
	readonly property var steps: Array(Config.mixerStepCount).fill(1)

	implicitWidth: root.contentWidth + Config.mixerPadding * 2
	implicitHeight: body.implicitHeight + Config.mixerPadding * 2

	onPickerChanged: {
		root.pickerIndex = 0;
	}

	readonly property var targetNodes: {
		const list = [];

		if (root.sink)
			list.push(root.sink);
		if (root.hasInput && root.source)
			list.push(root.source);

		return list.concat(root.streams(Config.mixerOnlyPlaying));
	}

	property bool keyboard: false
	property bool shift: false

	readonly property var selectedNode: root.targetNodes.length > 0
		? root.targetNodes[Util.clamp(root.targetIndex, 0, root.targetNodes.length - 1)]
		: null

	function same(a, b) {
		return !!a && !!b && a.id === b.id;
	}

	function shownStream(node) {
		return !!node && node.shown === true;
	}

	function playing(node) {
		return !!node && node.playing === true;
	}

	function streamHeld(node) {
		return !!node && root.held[node.id] !== undefined;
	}

	function streams(onlyPlaying) {
		return root.nodes.filter(function (node) {
			return root.shownStream(node) && (!onlyPlaying || root.playing(node));
		});
	}

	function streamVisible(node) {
		return root.shownStream(node) && (root.streamHeld(node) || !Config.mixerOnlyPlaying || root.playing(node));
	}

	function moveTarget(step) {
		const last = root.targetNodes.length - 1;

		if (last < 0)
			return;

		root.targetIndex = Util.clamp(root.targetIndex + step, 0, last);
	}

	function focusNode(node) {
		const nodes = root.targetNodes;

		for (let i = 0; i < nodes.length; i++) {
			if (root.same(nodes[i], node))
				root.targetIndex = i;
		}
	}

	function nodeAt(index) {
		const list = root.mix.nodes || [];

		return list[index] || null;
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

		root.keyboard = false;
		root.focusNode(node);

		const level = Util.clamp(fraction, 0, Config.mixerMaxVolume);

		if (!isFinite(level))
			return;

		if (node.volume !== undefined && Math.abs(node.volume - level) < 0.004)
			return;

		Yudae.audioVolume(node.id, level);
	}

	function beginDrag(node, fader, position) {
		const origin = fader.mapToItem(root, 0, 0);

		root.drag = { id: node ? node.id : -1, from: origin.x, width: fader.width, last: -1 };
	}

	function dragFader(node, fader, position, modifiers) {
		if (!node || !fader || root.drag.id !== node.id || !(root.drag.width > 0))
			return;

		const at = fader.mapToItem(root, position, 0).x - root.drag.from;

		if (!isFinite(at))
			return;

		if (root.drag.last >= 0 && Math.abs(at - root.drag.last) > root.drag.width / 2)
			return;

		root.drag = { id: root.drag.id, from: root.drag.from, width: root.drag.width, last: at };

		const fraction = Util.clamp(at / root.drag.width, 0, 1);
		const shift = (modifiers & Qt.ShiftModifier) !== 0;

		root.shift = shift;
		root.setFader(node, shift ? fraction : Util.roundStep(fraction, Config.mixerStepCount));
	}

	function nudgeVolume(step) {
		const node = root.selectedNode;

		if (!node)
			return;

		root.setFader(node, Util.clamp((node.volume || 0) + step, 0, Config.mixerMaxVolume));
	}

	Keys.onPressed: function (event) {
		if (event.key === Qt.Key_Shift)
			root.shift = true;

		if (Input.direction(event) !== "")
			root.keyboard = true;

		if (root.picker === "")
			Input.mixer(event, root);
		else
			Input.picker(event, root);
	}

	Keys.onReleased: function (event) {
		if (event.key === Qt.Key_Shift)
			root.shift = false;
	}

	function toggleMute(node) {
		if (!node)
			return;

		Yudae.audioMute(node.id, node.muted !== true);
	}

	function sortedDevices(input) {
		const active = input ? root.source : root.sink;
		const found = root.nodes.filter(function (node) {
			return !!node && !node.isStream && node.isSink !== !!input;
		});
		const at = found.findIndex(function (node) { return root.same(node, active); });

		if (at > 0)
			found.unshift(found.splice(at, 1)[0]);

		return found;
	}

	function iconFor(node) {
		if (!node)
			return "";

		return AppIcons.iconOf(node.appId, node.appIds);
	}

	function openPicker(direction) {
		root.picker = root.picker === direction ? "" : direction;
	}

	function closePicker() {
		root.picker = "";
		root.keyboard = false;
	}

	function makeDefault(direction, node) {
		if (!node)
			return;

		Yudae.audioDefault(node.id);

		root.picker = "";
	}

	property var held: ({})
	property var drag: ({ id: -1, from: 0, width: 0, last: -1 })

	function hold(node, until) {
		if (node)
			root.held = Object.assign({}, root.held, { [node.id]: until });
	}

	function pruneHolds() {
		const now = Date.now();
		const next = {};

		Object.keys(root.held).forEach(function (id) {
			if (root.held[id] > now)
				next[id] = root.held[id];
		});

		root.held = next;
	}

	component MixChannel: Item {
		id: channel

		property var node
		property string glyph: ""
		property bool appIcon: false
		readonly property bool muted: !!channel.node && channel.node.muted === true
		readonly property real volume: channel.node ? channel.node.volume : 0
		readonly property string percentText: channel.node ? channel.node.volumeText : "0%"
		readonly property string iconSource: channel.appIcon ? root.iconFor(channel.node) : ""

		readonly property bool selected: root.same(channel.node, root.selectedNode)
		readonly property real level: Util.clamp(channel.volume / Config.mixerMaxVolume, 0, 1)
		readonly property int step: Math.round(channel.level * Config.mixerStepCount) - 1

		height: Math.max(Config.mixerDeviceIconSize, Settings.fontSize)
		implicitHeight: height

		Highlight {
			id: hl

			active: channel.selected && root.keyboard
		}

		MouseArea {
			anchors.fill: parent

			onClicked: {
				root.keyboard = false;
				root.focusNode(channel.node);
			}
		}

		TextMetrics {
			id: sample

			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			text: "100%"
		}

		Item {
			id: iconSlot

			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			width: Config.mixerDeviceIconSize
			height: Config.mixerDeviceIconSize

			AppIcon {
				anchors.centerIn: parent
				implicitSize: Config.mixerIconSize
				visible: channel.iconSource !== ""
				opacity: channel.muted ? 0.45 : 1
				source: channel.iconSource
			}

			Text {
				anchors.centerIn: parent
				visible: channel.iconSource === ""
				font.family: Config.fontFamily
				font.pixelSize: Config.mixerIconSize
				color: channel.muted ? Config.muted : Config.foreground
				text: channel.glyph
			}
		}

		Text {
			id: linePercent

			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			width: sample.width
			horizontalAlignment: Text.AlignRight
			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: channel.muted && !hl.active ? Config.muted : hl.ink
			text: channel.percentText
		}

		Item {
			id: lineFader

			anchors.left: iconSlot.right
			anchors.leftMargin: Config.mixerListGap
			anchors.right: linePercent.left
			anchors.rightMargin: Config.mixerListGap
			anchors.verticalCenter: parent.verticalCenter
			height: parent.height

			StepBar {
				anchors.verticalCenter: parent.verticalCenter
				anchors.left: parent.left
				anchors.right: parent.right
				height: Config.mixerFaderThickness
				model: root.steps
				selected: channel.step
				level: root.shift ? channel.level : -1
				ink: channel.muted ? Config.muted : Config.foreground
			}

			MouseArea {
				anchors.fill: parent
				anchors.topMargin: -Config.mixerHitPad
				anchors.bottomMargin: -Config.mixerHitPad
				preventStealing: true

				onPressed: (mouse) => {
					root.beginDrag(channel.node, lineFader, mouse.x);
					root.dragFader(channel.node, lineFader, mouse.x, mouse.modifiers);
				}
				onPositionChanged: (mouse) => root.dragFader(channel.node, lineFader, mouse.x, mouse.modifiers)
			}
		}
	}

	component DeviceLine: Item {
		id: line

		property var node
		property string glyph: ""
		property bool recording: false
		property var onActivate

		readonly property bool muted: !!line.node && line.node.muted === true
		readonly property real volume: line.node ? line.node.volume : 0
		readonly property string percentText: line.node ? line.node.volumeText : "0%"
		readonly property bool selected: root.same(line.node, root.selectedNode)
		readonly property real level: Util.clamp(line.volume / Config.mixerMaxVolume, 0, 1)
		readonly property int step: Math.round(line.level * Config.mixerStepCount) - 1

		height: Math.max(Config.mixerDeviceIconSize, Settings.fontSize)
		implicitHeight: height

		Highlight {
			id: hl

			active: line.selected && root.keyboard
		}

		MouseArea {
			anchors.left: parent.left
			anchors.top: parent.top
			anchors.bottom: parent.bottom
			width: Config.mixerDeviceIconSize
			hoverEnabled: true

			onClicked: {
				if (line.onActivate)
					line.onActivate();
			}
		}

		TextMetrics {
			id: sample

			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			text: "100%"
		}

		Item {
			id: iconSlot

			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			width: Config.mixerDeviceIconSize
			height: Config.mixerDeviceIconSize

			Text {
				id: lineGlyph

				anchors.centerIn: parent
				font.family: Config.fontFamily
				font.pixelSize: Config.mixerDeviceIconSize
				color: line.muted ? Config.muted : Config.foreground
				text: line.glyph
			}

			Rectangle {
				anchors.right: parent.right
				anchors.top: parent.top
				width: Config.mixerRecordDotSize
				height: Config.mixerRecordDotSize
				radius: width / 2
				color: Config.red
				visible: line.recording
			}
		}

		Text {
			id: linePercent

			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			width: sample.width
			horizontalAlignment: Text.AlignRight
			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: line.muted && !hl.active ? Config.muted : hl.ink
			text: line.percentText
		}

		Item {
			id: lineFader

			anchors.left: iconSlot.right
			anchors.leftMargin: Config.mixerListGap
			anchors.right: linePercent.left
			anchors.rightMargin: Config.mixerListGap
			anchors.verticalCenter: parent.verticalCenter
			height: parent.height

			StepBar {
				anchors.verticalCenter: parent.verticalCenter
				anchors.left: parent.left
				anchors.right: parent.right
				height: Config.mixerFaderThickness
				model: root.steps
				selected: line.step
				level: root.shift ? line.level : -1
				ink: line.muted ? Config.muted : Config.foreground
			}

			MouseArea {
				anchors.fill: parent
				anchors.topMargin: -Config.mixerHitPad
				anchors.bottomMargin: -Config.mixerHitPad
				preventStealing: true

				onPressed: (mouse) => {
					root.beginDrag(line.node, lineFader, mouse.x);
					root.dragFader(line.node, lineFader, mouse.x, mouse.modifiers);
				}
				onPositionChanged: (mouse) => root.dragFader(line.node, lineFader, mouse.x, mouse.modifiers)
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

		DeviceLine {
			id: sinkLine

			width: parent.width
			node: root.sink

			onActivate: function () {
				root.keyboard = false;
				root.openPicker("output");
			}
			glyph: Config.iconOutput
		}

		DeviceLine {
			id: sourceLine

			width: parent.width
			visible: root.hasInput && !root.compact
			node: root.source

			onActivate: function () {
				root.keyboard = false;
				root.openPicker("input");
			}
			glyph: Config.iconInput
			recording: root.recording
		}

		Repeater {
			model: root.nodes.length

			delegate: Item {
				id: holder

				required property int index

				readonly property var node: root.nodeAt(holder.index)
				readonly property bool shown: root.shownStream(holder.node)
				readonly property bool active: holder.shown && (!Config.mixerOnlyPlaying || root.playing(holder.node))
				visible: root.showApps && root.streamVisible(holder.node)
				width: parent.width
				height: channel.implicitHeight
				clip: true

				onActiveChanged: {
					if (!holder.active)
						root.hold(holder.node, Date.now() + Config.mixerHoldMs);
				}

				MixChannel {
					id: channel

					width: parent.width
					node: holder.shown ? holder.node : null
					glyph: Config.iconApp
					appIcon: holder.shown
				}
			}
		}
	}

	Item {
		id: sheet

		anchors.fill: parent
		visible: root.picker !== ""
		z: 10

		Rectangle {
			anchors.fill: parent
			color: Config.surface
		}

		Column {
			id: options

			anchors.left: parent.left
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			anchors.margins: Config.mixerPadding
			spacing: Config.mixerListGap

			Repeater {
				model: root.devices

				delegate: Item {
					id: option

					required property var modelData
					required property int index

					readonly property var node: option.modelData
					readonly property bool active: !!option.node && option.node.isDefault === true
					readonly property bool highlighted: option.index === root.pickerIndex

					width: options.width
					height: Config.mixerListRowHeight

					Highlight {
						active: option.highlighted
					}

					Text {
						id: optionGlyph

						anchors.left: parent.left
						anchors.verticalCenter: parent.verticalCenter
						font.family: Config.fontFamily
						font.pixelSize: Config.mixerIconSize
						color: option.active || option.highlighted ? Config.foreground : Config.muted
						text: root.picker === "input" ? Config.iconInput : Config.iconOutput
					}

					Text {
						anchors.left: optionGlyph.right
						anchors.leftMargin: Config.mixerListGap
						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
						elide: Text.ElideRight
						font.family: Config.fontFamily
						font.pixelSize: Settings.fontSize
						color: option.active || option.highlighted ? Config.launcherHighlightText : Config.muted
						text: option.node ? option.node.description : ""
					}
				}
			}
		}
	}
}
