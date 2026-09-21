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
	property string picker: ""
	property int page: 0
	property int targetIndex: 0
	property int pickerIndex: 0

	signal closeRequested()

	focus: true

	readonly property real channelsMaxWidth: Config.mixerVisibleChannels * Config.mixerChannelWidth + (Config.mixerVisibleChannels - 1) * Config.mixerChannelGap
	readonly property real idleWidth: Config.mixerIdleChannels * Config.mixerChannelWidth + (Config.mixerIdleChannels - 1) * Config.mixerChannelGap
	readonly property real contentWidth: Math.max(root.hasApps ? apps.implicitWidth : 0, root.idleWidth)
	readonly property real pageStep: Config.mixerVisibleChannels * (Config.mixerChannelWidth + Config.mixerChannelGap)
	readonly property bool pageable: content.implicitWidth > root.channelsMaxWidth
	readonly property int lastPage: Util.pageCount(content.implicitWidth, root.channelsMaxWidth, root.pageStep) - 1
	readonly property var devices: root.picker === "" ? [] : root.sortedDevices(root.picker === "input")
	readonly property real offset: Util.pageOffset(root.page, content.implicitWidth, root.channelsMaxWidth, root.pageStep)
	readonly property bool hasApps: outputs.implicitWidth > 0
	readonly property bool recording: root.runningInput.length > 0

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
		if (root.source)
			list.push(root.source);

		return list;
	}

	readonly property var selectedNode: root.targetNodes.length > 0
		? root.targetNodes[Util.clamp(root.targetIndex, 0, root.targetNodes.length - 1)]
		: null

	function moveTarget(step) {
		const last = root.targetNodes.length - 1;

		if (last < 0)
			return;

		root.targetIndex = Util.clamp(root.targetIndex + step, 0, last);
	}

	function nudgeVolume(step) {
		const node = root.selectedNode;

		if (!node || !node.audio)
			return;

		node.audio.volume = Util.clamp(node.audio.volume + step, 0, Config.mixerMaxVolume);
	}

	Keys.onPressed: function (event) {
		if (root.picker === "")
			Input.mixer(event, root);
		else
			Input.picker(event, root);
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

		implicitWidth: Config.mixerChannelWidth
		implicitHeight: stack.implicitHeight
		width: implicitWidth
		height: implicitHeight

		Highlight {
			id: hl

			active: channel.selected
		}

		Column {
			id: stack

			width: parent.width
			spacing: Config.mixerChannelGap

			Item {
				id: fader

				width: parent.width
				height: Config.mixerFaderHeight

				Meter {
					anchors.horizontalCenter: parent.horizontalCenter
					anchors.top: parent.top
					anchors.bottom: parent.bottom
					width: Config.mixerFaderThickness
					vertical: true
					level: channel.level
					fill: channel.muted ? Config.muted : Config.foreground
				}
			}

			Text {
				width: parent.width
				horizontalAlignment: Text.AlignHCenter
				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
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

		readonly property bool selected: System.sameNode(line.node, root.selectedNode)
		readonly property real level: Util.clamp(line.volume / Config.mixerMaxVolume, 0, 1)
		readonly property int percent: Math.round(line.volume * 100)

		height: Math.max(Config.mixerDeviceIconSize, Config.fontSize)
		implicitHeight: height

		Highlight {
			id: hl

			active: line.selected
		}

		TextMetrics {
			id: sample

			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
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
			font.pixelSize: Config.fontSize
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

			Meter {
				anchors.verticalCenter: parent.verticalCenter
				anchors.left: parent.left
				anchors.right: parent.right
				height: Config.mixerFaderThickness
				level: line.level
				fill: line.muted ? Config.muted : Config.foreground
			}
		}
	}

	component Meter: Rectangle {
		id: meter

		property real level: 0
		property bool vertical: false
		property color fill: Config.foreground

		radius: 0
		color: Config.dim

		Rectangle {
			id: filled

			radius: 0
			color: meter.fill
			width: meter.vertical ? meter.width : meter.width * meter.level
			height: meter.vertical ? meter.height * meter.level : meter.height
			anchors.bottom: meter.vertical ? meter.bottom : undefined
			anchors.horizontalCenter: meter.vertical ? meter.horizontalCenter : undefined
			anchors.left: meter.vertical ? undefined : meter.left
			anchors.verticalCenter: meter.vertical ? undefined : meter.verticalCenter
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

							visible: implicitWidth > 0
							spacing: Config.mixerChannelGap

							Repeater {
								model: Pipewire.nodes

								delegate: Item {
									id: holder

									required property var modelData

									readonly property var node: holder.modelData
									readonly property bool shown: System.shownStream(holder.node)
									readonly property bool active: holder.shown && (!Config.mixerOnlyPlaying || System.streamPlaying(holder.node, root.runningOutput))
									readonly property bool held: root.held[holder.node ? holder.node.id : -1] !== undefined

									visible: holder.shown && (holder.active || holder.held)
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
				glyph: Config.iconOutput
				muted: System.nodeMuted(root.sink)
				volume: System.nodeVolume(root.sink)
			}

			DeviceLine {
				id: sourceLine

				width: parent.width
				node: root.source
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
						font.pixelSize: Config.fontSize
						color: option.active || option.highlighted ? Config.launcherHighlightText : Config.muted
						text: option.node ? option.node.description : ""
					}
				}
			}
		}
	}
}
