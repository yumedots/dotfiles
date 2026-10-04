import QtQuick
import Quickshell
import qs.ui
import qs

Item {
	id: root

	property var player: null
	property real position: 0

	readonly property bool playing: root.player !== null && root.player.isPlaying
	readonly property string title: root.player !== null ? root.player.trackTitle : ""
	readonly property string artist: root.player !== null ? root.player.trackArtist : ""
	readonly property string album: root.player !== null ? root.player.trackAlbum : ""
	readonly property string art: root.player !== null ? root.player.trackArtUrl : ""
	readonly property var clock: Media.clock(root.player, root.position)

	focus: true

	signal closeRequested()

	implicitWidth: Config.mediaTooltipWidth + Config.mediaTooltipPadding * 2
	implicitHeight: body.implicitHeight + Config.mediaTooltipPadding * 2

	function readPosition() {
		root.position = root.player !== null ? root.player.position : 0;
	}

	function send(action) {
		const command = Media.command([root.player], action);

		if (command.length > 0)
			Quickshell.execDetached(command);
	}

	function togglePlay() {
		root.send("playPause");
	}

	function previous() {
		root.send("previous");
	}

	function next() {
		root.send("next");
	}

	onPlayerChanged: root.readPosition()

	Keys.onPressed: function (event) {
		Input.media(event, root);
	}

	Timer {
		interval: Config.mediaTickMs
		running: root.playing
		repeat: true
		triggeredOnStart: true
		onTriggered: root.readPosition()
	}

	component Button: Item {
		id: button

		property string glyph: ""
		property var onActivate

		width: Config.mediaButtonGlyphSize
		height: Config.mediaButtonGlyphSize

		Text {
			anchors.centerIn: parent

			font.family: Config.fontFamily
			font.pixelSize: Config.mediaButtonGlyphSize
			color: Config.foreground
			text: button.glyph
		}

		MouseArea {
			id: hit

			anchors.fill: parent
			anchors.margins: -Config.barHitPadding

			onClicked: {
				if (button.onActivate)
					button.onActivate();
			}
		}
	}

	Column {
		id: body

		x: Config.mediaTooltipPadding
		y: Config.mediaTooltipPadding
		width: Config.mediaTooltipWidth
		spacing: Config.mediaRowGap

		Item {
			id: artSlot

			width: parent.width
			height: Config.mediaArtHeight

			Item {
				id: art

				anchors.fill: parent

				Rectangle {
					anchors.fill: parent
					color: Config.launcherSearchBox
				}

				Text {
					anchors.centerIn: parent
					visible: root.art === "" || artwork.status !== Image.Ready
					font.family: Config.fontFamily
					font.pixelSize: Math.round(art.height * 0.2)
					color: Config.muted
					text: Config.iconApp
				}

				Image {
					id: artwork

					anchors.fill: parent
					cache: false
					sourceSize.width: Config.mediaArtHeight * 2
					fillMode: Image.PreserveAspectCrop
					source: root.art
				}
			}

			Rectangle {
				anchors.fill: parent
				color: "transparent"
				border.width: 1
				border.color: Config.dim
			}
		}

		Rectangle {
			width: parent.width
			height: Config.mediaSeparator
			color: Config.mediaSeparatorColor
		}

		Column {
			width: parent.width
			spacing: Config.mediaLineGap

			Text {
				width: parent.width
				horizontalAlignment: Text.AlignHCenter
				elide: Text.ElideRight
				font.family: Config.fontFamily
				font.pixelSize: Config.mediaTitleSize
				color: root.player !== null ? Config.foreground : Config.muted
				text: root.player !== null && root.title !== "" ? root.title : Config.mediaEmpty
			}

			Text {
				width: parent.width
				visible: root.artist !== ""
				horizontalAlignment: Text.AlignHCenter
				elide: Text.ElideRight
				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.foreground
				text: root.artist
			}

			Text {
				width: parent.width
				visible: root.album !== ""
				horizontalAlignment: Text.AlignHCenter
				elide: Text.ElideRight
				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.muted
				text: root.album
			}
		}

		Rectangle {
			width: parent.width
			height: Config.mediaSeparator
			color: Config.mediaSeparatorColor
		}

		Item {
			id: times

			width: parent.width
			height: elapsed.implicitHeight
			visible: root.clock.known

			Text {
				id: elapsed

				anchors.left: parent.left

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.foreground
				text: root.clock.elapsed
			}

			Text {
				anchors.right: parent.right

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.muted
				text: root.clock.total
			}
		}

		StepBar {
			width: parent.width
			visible: root.clock.known
			level: root.clock.percent / 100
		}

		Item {
			id: controls

			width: parent.width
			height: Config.mediaButtonGlyphSize
			visible: root.player !== null

			Row {
				anchors.horizontalCenter: parent.horizontalCenter
				spacing: Config.mediaButtonGap

				Button {
					glyph: Config.iconPrev

					onActivate: function () {
						root.previous();
					}
				}

				Button {
					glyph: root.playing ? Config.iconPause : Config.iconPlay

					onActivate: function () {
						root.togglePlay();
					}
				}

				Button {
					glyph: Config.iconNext

					onActivate: function () {
						root.next();
					}
				}
			}
		}
	}
}
