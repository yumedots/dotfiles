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

		width: Config.mediaButtonSize
		height: Config.mediaButtonSize

		Text {
			anchors.centerIn: parent
			font.family: Config.fontFamily
			font.pixelSize: Config.mediaButtonGlyphSize
			color: hit.containsMouse ? Config.foreground : Config.muted
			text: button.glyph
		}

		MouseArea {
			id: hit

			anchors.fill: parent
			hoverEnabled: true

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
			id: head

			width: parent.width
			height: Config.mediaArtSize

			Item {
				id: art

				width: Config.mediaArtSize
				height: Config.mediaArtSize

				Rectangle {
					anchors.fill: parent
					color: Config.launcherSearchBox
				}

				Text {
					anchors.centerIn: parent
					visible: root.art === "" || artwork.status !== Image.Ready
					font.family: Config.fontFamily
					font.pixelSize: Math.round(art.width * 0.5)
					color: Config.muted
					text: Config.iconApp
				}

				Image {
					id: artwork

					anchors.fill: parent
					cache: false
					fillMode: Image.PreserveAspectCrop
					source: root.art
				}
			}

			Column {
				id: text

				anchors.left: art.right
				anchors.leftMargin: Config.mediaTextGap
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				spacing: Config.mediaLineGap

				Text {
					width: parent.width
					elide: Text.ElideRight
					font.family: Config.fontFamily
					font.pixelSize: Config.mediaTitleSize
					color: root.player !== null ? Config.foreground : Config.muted
					text: root.player !== null && root.title !== "" ? root.title : Config.mediaEmpty
				}

				Text {
					width: parent.width
					visible: root.artist !== ""
					elide: Text.ElideRight
					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: Config.foreground
					text: root.artist
				}

				Text {
					width: parent.width
					visible: root.album !== ""
					elide: Text.ElideRight
					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: Config.foreground
					text: root.album
				}
			}
		}

		Row {
			id: buttons

			visible: root.player !== null
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

		Item {
			id: progress

			visible: root.clock.known
			width: parent.width
			height: Config.mediaProgressHeight

			Rectangle {
				anchors.fill: parent
				color: Config.dim
			}

			Rectangle {
				anchors.left: parent.left
				anchors.top: parent.top
				anchors.bottom: parent.bottom
				width: parent.width * root.clock.percent / 100
				color: Config.foreground
			}
		}
	}
}
