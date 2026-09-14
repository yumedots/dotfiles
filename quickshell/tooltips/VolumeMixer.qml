import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import qs.ui
import qs
import qs.services

Item {
	id: root

	readonly property var sink: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink : root.firstDevice(false)
	readonly property var source: Pipewire.defaultAudioSource ? Pipewire.defaultAudioSource : root.firstDevice(true)
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
	readonly property int lastPage: Helpers.pageCount(content.implicitWidth, root.channelsMaxWidth, root.pageStep) - 1
	readonly property var devices: root.picker === "" ? [] : root.sortedDevices(root.picker === "input")
	readonly property real offset: Helpers.pageOffset(root.page, content.implicitWidth, root.channelsMaxWidth, root.pageStep)
	readonly property bool hasApps: outputs.implicitWidth > 0
	readonly property bool recording: root.runningInput.length > 0

	implicitWidth: root.contentWidth + Config.mixerPadding * 2
	implicitHeight: body.implicitHeight + Config.mixerPadding * 2

	onLastPageChanged: root.page = Math.min(root.page, root.lastPage)
	onPickerChanged: root.pickerIndex = 0

	readonly property var targetNodes: {
		const nodes = Pipewire.nodes.values ? Pipewire.nodes.values : [];
		const list = [];

		for (let i = 0; i < nodes.length; i++) {
			const node = nodes[i];

			if (root.shownStream(node) && (!Config.mixerOnlyPlaying || root.playing(node)))
				list.push(node);
		}

		if (root.sink)
			list.push(root.sink);
		if (root.source)
			list.push(root.source);

		return list;
	}

	readonly property var selectedNode: root.targetNodes.length > 0
		? root.targetNodes[Math.max(0, Math.min(root.targetIndex, root.targetNodes.length - 1))]
		: null

	function moveTarget(step) {
		const last = root.targetNodes.length - 1;

		if (last < 0)
			return;

		root.targetIndex = Math.max(0, Math.min(last, root.targetIndex + step));
	}

	function nudgeVolume(step) {
		const node = root.selectedNode;

		if (!node || !node.audio)
			return;

		node.audio.volume = Math.max(0, Math.min(node.audio.volume + step, Config.mixerMaxVolume));
	}

	Keys.onPressed: function (event) {
		if (event.key === Qt.Key_Escape) {
			if (root.picker !== "")
				root.picker = "";
			else
				root.closeRequested();

			event.accepted = true;
			return;
		}

		if (root.picker !== "") {
			if (event.text === "j" || event.key === Qt.Key_Down)
				root.pickerIndex = Math.min(Math.max(0, root.devices.length - 1), root.pickerIndex + 1);
			else if (event.text === "k" || event.key === Qt.Key_Up)
				root.pickerIndex = Math.max(0, root.pickerIndex - 1);
			else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
				root.makeDefault(root.picker, root.devices[root.pickerIndex]);
			else
				return;

			event.accepted = true;
			return;
		}

		if (event.text === "h" || event.key === Qt.Key_Left)
			root.moveTarget(-1);
		else if (event.text === "l" || event.key === Qt.Key_Right)
			root.moveTarget(1);
		else if (event.text === "j")
			root.nudgeVolume(-Config.mixerStep);
		else if (event.text === "k")
			root.nudgeVolume(Config.mixerStep);
		else if (event.text === "m")
			root.toggleMute(root.selectedNode);
		else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
			if (root.sameNode(root.selectedNode, root.sink))
				root.openPicker("output");
			else if (root.sameNode(root.selectedNode, root.source))
				root.openPicker("input");
			else
				return;
		} else
			return;

		event.accepted = true;
	}

	function setVolume(node, value) {
		if (!node || !node.audio)
			return;

		node.audio.volume = Math.max(0, Math.min(value, Config.mixerMaxVolume));
	}

	function toggleMute(node) {
		if (!node || !node.audio)
			return;

		node.audio.muted = !node.audio.muted;
	}

	function inputStream(node) {
		if (!node)
			return false;

		return Helpers.isInputStream(node.isStream, node.properties ? node.properties["media.class"] : "");
	}

	function shownStream(node) {
		return !!node && node.ready && node.isStream && !root.inputStream(node);
	}

	function playing(node) {
		return node ? root.runningOutput.indexOf(node.id) >= 0 : false;
	}

	function audioDevices(input) {
		const nodes = Pipewire.nodes.values ? Pipewire.nodes.values : [];
		const found = [];

		for (let i = 0; i < nodes.length; i++) {
			const node = nodes[i];

			if (!node || node.isStream || !node.audio || node.isSink === !!input)
				continue;

			found.push(node);
		}

		return found;
	}

	function firstDevice(input) {
		const found = root.audioDevices(input);

		return found.length > 0 ? found[0] : null;
	}

	function sameNode(a, b) {
		return !!a && !!b && a.id === b.id;
	}

	function switchable(input) {
		return root.audioDevices(input).length > 1;
	}

	function sortedDevices(input) {
		const found = root.audioDevices(input);
		const active = input ? root.source : root.sink;
		let at = -1;

		for (let i = 0; i < found.length; i++) {
			if (root.sameNode(found[i], active))
				at = i;
		}

		if (at > 0) {
			found.splice(at, 1);
			found.unshift(active);
		}

		return found;
	}

	function iconFor(node) {
		if (!node)
			return "";

		const app = Helpers.streamApp(node.properties);

		return appIcons.iconOf(app.name, app.icons);
	}

	function openPicker(direction) {
		root.picker = root.picker === direction ? "" : direction;
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

	AppIcons {
		id: appIcons
	}

	Timer {
		interval: Config.mixerPollMs
		running: root.onScreen
		repeat: true
		triggeredOnStart: true
		onTriggered: if (!streamPoll.running) streamPoll.running = true
	}

	Process {
		id: streamPoll

		command: ["pw-dump"]

		stdout: StdioCollector {
			onStreamFinished: {
				root.runningOutput = Helpers.parseRunningStreams(text, "output");
				root.runningInput = Helpers.parseRunningStreams(text, "input");
			}
		}
	}

	component MixChannel: Item {
		id: channel

		property var node
		property string glyph: ""
		property bool appIcon: false
		property bool muted: false
		property real volume: 0

		signal moved(real value)
		signal toggled()

		readonly property bool selected: root.sameNode(channel.node, root.selectedNode)
		readonly property string iconSource: channel.appIcon ? root.iconFor(channel.node) : ""
		readonly property int percent: Math.round(channel.volume * 100)
		readonly property real level: Math.max(0, Math.min(channel.volume / Config.mixerMaxVolume, 1))

		implicitWidth: Config.mixerChannelWidth
		implicitHeight: stack.implicitHeight
		width: implicitWidth
		height: implicitHeight

		Column {
			id: stack

			width: parent.width
			spacing: Config.mixerChannelGap

			Item {
				id: fader

				width: parent.width
				height: Config.mixerFaderHeight

				Rectangle {
					id: track

					anchors.horizontalCenter: parent.horizontalCenter
					anchors.top: parent.top
					anchors.bottom: parent.bottom
					width: Config.mixerFaderThickness
					radius: width / 2
					color: Config.dim
				}

				Rectangle {
					anchors.horizontalCenter: track.horizontalCenter
					anchors.bottom: track.bottom
					width: track.width
					height: track.height * channel.level
					radius: track.radius
					color: channel.muted ? Config.muted : Config.foreground
				}
			}

			Text {
				width: parent.width
				horizontalAlignment: Text.AlignHCenter
				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
				color: channel.selected ? Config.launcherHighlightText : (channel.muted ? Config.muted : Config.foreground)
				text: channel.percent + "%"
			}

			Item {
				id: badge

				width: parent.width
				height: Config.mixerIconSize

				IconImage {
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
		property bool switchable: false
		property real volume: 0

		signal moved(real value)
		signal toggled()
		signal opened()

		readonly property bool selected: root.sameNode(line.node, root.selectedNode)
		readonly property real level: Math.max(0, Math.min(line.volume / Config.mixerMaxVolume, 1))
		readonly property int percent: Math.round(line.volume * 100)

		height: Math.max(Config.mixerDeviceIconSize, Config.fontSize)
		implicitHeight: height

		Text {
			id: sample

			visible: false
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
			width: sample.implicitWidth
			horizontalAlignment: Text.AlignRight
			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: line.selected ? Config.launcherHighlightText : (line.muted ? Config.muted : Config.foreground)
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

			Rectangle {
				id: lineTrack

				anchors.verticalCenter: parent.verticalCenter
				anchors.left: parent.left
				anchors.right: parent.right
				height: Config.mixerFaderThickness
				radius: height / 2
				color: Config.dim
			}

			Rectangle {
				anchors.verticalCenter: lineTrack.verticalCenter
				anchors.left: lineTrack.left
				width: lineTrack.width * line.level
				height: lineTrack.height
				radius: height / 2
				color: line.muted ? Config.muted : Config.foreground
			}
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

				Item {
					id: prevStrip

					visible: root.pageable
					width: visible ? Config.mixerArrowSize : 0
					implicitWidth: width
					height: content.implicitHeight

					Text {
						anchors.centerIn: parent
						font.family: Config.fontFamily
						font.pixelSize: Config.mixerArrowSize
						color: Config.foreground
						text: Config.iconPrev
						visible: root.page > 0
					}
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

									property bool held: false

									readonly property var node: holder.modelData
									readonly property bool shown: root.shownStream(holder.node)
									readonly property bool active: holder.shown && (!Config.mixerOnlyPlaying || root.playing(holder.node))

									visible: holder.shown && holder.held
									width: holder.shown && holder.held ? channel.implicitWidth : 0
									height: channel.implicitHeight
									clip: true

									Component.onCompleted: holder.held = holder.active

									onActiveChanged: {
										if (holder.active) {
											releaseTimer.stop();
											holder.held = true;
										} else
											releaseTimer.restart();
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
										muted: holder.shown && holder.node.audio ? holder.node.audio.muted : false
										volume: holder.shown && holder.node.audio ? holder.node.audio.volume : 0
										onMoved: (value) => root.setVolume(holder.node, value)
										onToggled: root.toggleMute(holder.node)
									}

									Timer {
										id: releaseTimer
										interval: Config.mixerHoldMs
										onTriggered: holder.held = false
									}
								}
							}
						}
					}
				}

				Item {
					id: nextStrip

					visible: root.pageable
					width: visible ? Config.mixerArrowSize : 0
					implicitWidth: width
					height: content.implicitHeight

					Text {
						anchors.centerIn: parent
						font.family: Config.fontFamily
						font.pixelSize: Config.mixerArrowSize
						color: Config.foreground
						text: Config.iconNext
						visible: root.page < root.lastPage
					}
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
				switchable: root.switchable(false)
				muted: root.sink && root.sink.audio ? root.sink.audio.muted : false
				volume: root.sink && root.sink.audio ? root.sink.audio.volume : 0
				onMoved: (value) => root.setVolume(root.sink, value)
				onToggled: root.toggleMute(root.sink)
				onOpened: root.openPicker("output")
			}

			DeviceLine {
				id: sourceLine

				width: parent.width
				node: root.source
				glyph: Config.iconInput
				recording: root.recording
				switchable: root.switchable(true)
				muted: root.source && root.source.audio ? root.source.audio.muted : false
				volume: root.source && root.source.audio ? root.source.audio.volume : 0
				onMoved: (value) => root.setVolume(root.source, value)
				onToggled: root.toggleMute(root.source)
				onOpened: root.openPicker("input")
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
			anchors.top: parent.top
			anchors.margins: Config.mixerPadding
			spacing: Config.mixerListGap

			Repeater {
				model: root.devices

				delegate: Item {
					id: option

					required property var modelData

					readonly property var node: option.modelData
					readonly property bool active: root.sameNode(option.node, root.picker === "input" ? root.source : root.sink)
					readonly property bool highlighted: option.index === root.pickerIndex

					width: options.width
					height: Config.mixerListRowHeight

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
