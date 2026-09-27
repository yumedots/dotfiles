import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.ui
import qs
import qs.services

Item {
	id: root

	readonly property var nodes: Pipewire.nodes.values ? Pipewire.nodes.values : []
	readonly property var sink: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink : System.firstDevice(root.nodes, false)
	readonly property var source: Pipewire.defaultAudioSource ? Pipewire.defaultAudioSource : System.firstDevice(root.nodes, true)
	readonly property bool onScreen: root.Window.window ? root.Window.window.visible : false

	property var runningOutput: []
	property var runningInput: []
	property bool hasInput: false
	property string picker: ""
	property int page: 0
	property int targetIndex: 0
	property int pickerIndex: 0

	signal closeRequested()

	focus: true

	property bool shown: false

	onShownChanged: if (!root.shown) {
		root.keyboard = false;
		root.shift = false;
	}

	readonly property real channelsMaxWidth: Config.mixerVisibleChannels * Config.mixerChannelWidth + (Config.mixerVisibleChannels - 1) * Config.mixerChannelGap
	readonly property real idleWidth: Config.mixerIdleChannels * Config.mixerChannelWidth + (Config.mixerIdleChannels - 1) * Config.mixerChannelGap
	readonly property real contentWidth: Math.max(root.hasApps ? apps.implicitWidth : 0, root.idleWidth)
	readonly property real pageStep: Config.mixerVisibleChannels * (Config.mixerChannelWidth + Config.mixerChannelGap)
	readonly property bool pageable: content.implicitWidth > root.channelsMaxWidth
	readonly property int lastPage: Util.pageCount(content.implicitWidth, root.channelsMaxWidth, root.pageStep) - 1
	readonly property var devices: root.picker === "" ? [] : root.sortedDevices(root.picker === "input")
	readonly property real offset: Util.pageOffset(root.page, content.implicitWidth, root.channelsMaxWidth, root.pageStep)
	readonly property bool hasApps: System.anyStreamVisible(root.nodes, root.runningOutput, Config.mixerOnlyPlaying, root.held)
	readonly property bool recording: root.runningInput.length > 0
	readonly property var steps: Array(Config.mixerStepCount).fill(1)

	implicitWidth: root.contentWidth + Config.mixerPadding * 2
	implicitHeight: body.implicitHeight + Config.mixerPadding * 2

	onLastPageChanged: root.page = Math.min(root.page, root.lastPage)
	onPickerChanged: {
		root.pickerIndex = 0;
	}

	readonly property var targetNodes: {
		const list = System.streamNodes(root.nodes, root.runningOutput, Config.mixerOnlyPlaying);

		if (root.sink)
			list.push(root.sink);
		if (root.hasInput && root.source)
			list.push(root.source);

		return list;
	}

	property bool keyboard: false
	property bool shift: false

	readonly property var selectedNode: root.targetNodes.length > 0
		? root.targetNodes[Util.clamp(root.targetIndex, 0, root.targetNodes.length - 1)]
		: null

	function moveTarget(step) {
		const last = root.targetNodes.length - 1;

		if (last < 0)
			return;

		root.targetIndex = Util.clamp(root.targetIndex + step, 0, last);
	}

	function focusNode(node) {
		const nodes = root.targetNodes;

		for (let i = 0; i < nodes.length; i++) {
			if (System.sameNode(nodes[i], node))
				root.targetIndex = i;
		}
	}

	function setFader(node, fraction) {
		root.keyboard = false;
		root.focusNode(node);
		System.setNodeVolume(node, fraction, Config.mixerMaxVolume);
	}

	// ponytail: the bar moves in whole tenths, and holding shift drops back to the
	// free fader for a percent that is not on a tenth. A value landing between
	// steps draws as one solid bar instead of the cut one, see StepBar.level.
	function dragFader(node, position, size, vertical, modifiers) {
		const fraction = vertical ? 1 - position / size : position / size;
		const shift = (modifiers & Qt.ShiftModifier) !== 0;

		root.shift = shift;
		root.setFader(node, shift ? fraction : Util.roundStep(fraction, Config.mixerStepCount));
	}

	function nudgeVolume(step) {
		const node = root.selectedNode;

		if (!node || !node.audio)
			return;

		node.audio.volume = Util.clamp(node.audio.volume + step, 0, Config.mixerMaxVolume);
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
		if (!node || !node.audio)
			return;

		node.audio.muted = !node.audio.muted;
	}

	function sortedDevices(input) {
		return System.sortedDevices(root.nodes, input, input ? root.source : root.sink);
	}

	function iconFor(node) {
		if (!node)
			return "";

		const app = System.streamApp(node.properties);

		return AppIcons.iconOf(app.name, app.icons);
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

		if (direction === "input")
			Pipewire.preferredDefaultAudioSource = node;
		else
			Pipewire.preferredDefaultAudioSink = node;

		root.picker = "";
	}

	PwObjectTracker {
		objects: [root.sink, root.source]
	}

	Timer {
		interval: Config.mixerPollMs
		running: root.onScreen
		repeat: true
		triggeredOnStart: true
		onTriggered: if (!streamPoll.running) streamPoll.running = true
	}

	// ponytail: holds expire on the poll tick instead of their own timers, so one
	// list replaces one timer per channel. Ceiling: a channel can linger up to
	// mixerPollMs past its hold; give it its own timer again if that ever shows.
	property var held: ({})

	function hold(node, until) {
		if (node)
			root.held = System.holdStream(root.held, node.id, until);
	}

	Request {
		id: streamPoll

		command: ["pw-dump"]

		onDone: function (text) {
			root.runningOutput = System.parseRunningStreams(text, "output");
			root.runningInput = System.parseRunningStreams(text, "input");
			root.hasInput = System.hasMicrophone(text);
			root.held = System.pruneHolds(root.held, Date.now());
		}
	}

	component MixChannel: Item {
		id: channel

		property var node
		property string glyph: ""
		property bool appIcon: false
		property bool muted: false
		property real volume: 0

		readonly property bool selected: System.sameNode(channel.node, root.selectedNode)
		readonly property string iconSource: channel.appIcon ? root.iconFor(channel.node) : ""
		readonly property int percent: Math.round(channel.volume * 100)
		readonly property real level: Util.clamp(channel.volume / Config.mixerMaxVolume, 0, 1)
		readonly property int step: Math.round(channel.level * Config.mixerStepCount) - 1

		implicitWidth: Config.mixerChannelWidth
		implicitHeight: stack.implicitHeight
		width: implicitWidth
		height: implicitHeight

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

		Column {
			id: stack

			width: parent.width
			spacing: Config.mixerChannelGap

			Item {
				id: fader

				width: parent.width
				height: Config.mixerFaderHeight

				StepBar {
					anchors.horizontalCenter: parent.horizontalCenter
					anchors.top: parent.top
					anchors.bottom: parent.bottom
					width: Config.mixerFaderThickness
					vertical: true
					model: root.steps
					selected: channel.step
					level: root.shift ? channel.level : -1
					ink: channel.muted ? Config.muted : Config.foreground
				}

				MouseArea {
					anchors.fill: parent
					anchors.leftMargin: -Config.mixerHitPad
					anchors.rightMargin: -Config.mixerHitPad
					preventStealing: true

					onPressed: (mouse) => root.dragFader(channel.node, mouse.y, fader.height, true, mouse.modifiers)
					onPositionChanged: (mouse) => root.dragFader(channel.node, mouse.y, fader.height, true, mouse.modifiers)
				}
			}

			Text {
				width: parent.width
				horizontalAlignment: Text.AlignHCenter
				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: channel.muted && !hl.active ? Config.muted : hl.ink
				text: channel.percent + "%"
			}

			Item {
				id: badge

				width: parent.width
				height: Config.mixerIconSize

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
		}
	}

	component DeviceLine: Item {
		id: line

		property var node
		property string glyph: ""
		property bool muted: false
		property bool recording: false
		property real volume: 0
		property var onActivate

		readonly property bool selected: System.sameNode(line.node, root.selectedNode)
		readonly property real level: Util.clamp(line.volume / Config.mixerMaxVolume, 0, 1)
		readonly property int percent: Math.round(line.volume * 100)
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
			text: line.percent + "%"
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

				onPressed: (mouse) => root.dragFader(line.node, mouse.x, lineFader.width, false, mouse.modifiers)
				onPositionChanged: (mouse) => root.dragFader(line.node, mouse.x, lineFader.width, false, mouse.modifiers)
			}
		}
	}

	component PagerArrow: Item {
		id: arrow

		property string glyph: ""
		property bool lit: false
		property real rows: 0

		visible: root.pageable
		width: arrow.visible ? Config.mixerArrowSize : 0
		implicitWidth: width
		height: arrow.rows

		Text {
			anchors.centerIn: parent
			font.family: Config.fontFamily
			font.pixelSize: Config.mixerArrowSize
			color: Config.foreground
			text: arrow.glyph
			visible: arrow.lit
		}
	}

	Column {
		id: body

		anchors.left: parent.left
		anchors.top: parent.top
		anchors.margins: Config.mixerPadding
		width: root.contentWidth
		spacing: Config.mixerRowGap

		Item {
			id: appRow

			width: parent.width
			height: apps.implicitHeight
			implicitHeight: height
			visible: root.hasApps

			Row {
				id: apps

				anchors.horizontalCenter: parent.horizontalCenter
				spacing: Config.mixerArrowGap

				PagerArrow {
					glyph: Config.iconPrev
					lit: root.page > 0
					rows: content.implicitHeight
				}

				Item {
					id: window

					width: Math.min(content.implicitWidth, root.channelsMaxWidth)
					height: content.implicitHeight
					implicitWidth: width
					implicitHeight: height
					clip: true

					Row {
						id: content

						 x: -root.offset
						spacing: Config.mixerChannelGap

						Row {
							id: outputs

							spacing: Config.mixerChannelGap

							Repeater {
								model: Pipewire.nodes

								delegate: Item {
									id: holder

									required property var modelData

									readonly property var node: holder.modelData
									readonly property bool shown: System.shownStream(holder.node)
									readonly property bool active: holder.shown && (!Config.mixerOnlyPlaying || System.streamPlaying(holder.node, root.runningOutput))
									visible: System.streamVisible(holder.node, root.runningOutput, Config.mixerOnlyPlaying, root.held)
									width: holder.visible ? channel.implicitWidth : 0
									height: channel.implicitHeight
									clip: true

									onActiveChanged: {
										if (!holder.active)
											root.hold(holder.node, Date.now() + Config.mixerHoldMs);
									}

									PwObjectTracker {
										objects: holder.node && holder.node.isStream ? [holder.node] : []
									}

									MixChannel {
										id: channel

										width: parent.width
										node: holder.shown ? holder.node : null
										glyph: Config.iconApp
										appIcon: holder.shown
										muted: holder.shown && System.nodeMuted(holder.node)
										volume: holder.shown ? System.nodeVolume(holder.node) : 0
									}
								}
							}
						}
					}
				}

				PagerArrow {
					glyph: Config.iconNext
					lit: root.page < root.lastPage
					rows: content.implicitHeight
				}
			}
		}

		Column {
			id: lines

			width: parent.width
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
				muted: System.nodeMuted(root.sink)
				volume: System.nodeVolume(root.sink)
			}

			DeviceLine {
				id: sourceLine

				width: parent.width
				visible: root.hasInput
				node: root.source

				onActivate: function () {
					root.keyboard = false;
					root.openPicker("input");
				}
				glyph: Config.iconInput
				recording: root.recording
				muted: System.nodeMuted(root.source)
				volume: System.nodeVolume(root.source)
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

		PwObjectTracker {
			objects: root.devices
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
					readonly property bool active: System.sameNode(option.node, root.picker === "input" ? root.source : root.sink)
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
