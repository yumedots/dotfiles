import QtQuick
import qs.ui
import qs
import qs.services

Item {
	id: root

	readonly property var media: Yudae.mediaState
	readonly property bool playing: root.media.playing === true
	readonly property string title: root.media.title || ""
	readonly property string artist: root.media.artist || ""
	readonly property string album: root.media.album || ""
	readonly property string art: root.media.art || ""
	readonly property bool known: root.media.known === true
	readonly property bool present: (root.media.name || "") !== ""

	focus: true

	signal closeRequested()

	implicitWidth: Config.mediaTooltipWidth + Config.mediaTooltipPadding * 2
	implicitHeight: body.implicitHeight + Config.mediaTooltipPadding * 2

	function send(action) {
		Yudae.send({ cmd: { media: action } });
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

	Keys.onPressed: function (event) {
		Input.media(event, root);
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
				property string shown: ""

				Rectangle {
					anchors.fill: parent
					color: Config.launcherSearchBox
				}

				Text {
					anchors.centerIn: parent
					visible: art.shown === ""
					font.family: Config.fontFamily
					font.pixelSize: Math.round(art.height * 0.2)
					color: Config.muted
					text: Config.iconApp
				}

				Image {
					anchors.fill: parent
					cache: false
					sourceSize.width: Config.mediaArtHeight * 2
					fillMode: Image.PreserveAspectCrop
					source: art.shown
				}

				Image {
					id: incoming

					anchors.fill: parent
					cache: false
					sourceSize.width: Config.mediaArtHeight * 2
					fillMode: Image.PreserveAspectCrop
					source: root.art
					opacity: 0

					onStatusChanged: {
						if (status !== Image.Ready) {
							fade.stop();
							opacity = 0;
						}

						if (root.art === "")
							art.shown = "";
						else if (status === Image.Ready)
							fade.restart();
					}

					onOpacityChanged: if (opacity >= 1 && status === Image.Ready)
						art.shown = String(source);

					NumberAnimation {
						id: fade

						target: incoming
						property: "opacity"
						from: 0
						to: 1
						duration: Config.popupFadeMs
						easing.type: Easing.OutCubic
					}
				}
			}

			Rectangle {
				anchors.fill: parent
				color: "transparent"
				border.width: 1
				border.color: Config.dim
			}
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
				color: root.present ? Config.foreground : Config.muted
				text: root.title !== "" ? root.title : Config.mediaEmpty
			}

			Text {
				width: parent.width
				visible: root.artist !== "" || root.album !== ""
				horizontalAlignment: Text.AlignHCenter
				elide: Text.ElideRight
				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.foreground
				text: [root.artist, root.album].filter(s => s !== "").join(" - ")
			}
		}

		Item {
			id: times

			width: parent.width
			height: elapsed.implicitHeight
			visible: root.known

			Text {
				id: elapsed

				anchors.left: parent.left

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.foreground
				text: root.media.elapsed || ""
			}

			Text {
				anchors.right: parent.right

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.muted
				text: root.media.total || ""
			}
		}

		StepBar {
			width: parent.width
			visible: root.known
			level: (root.media.percent || 0) / 100
		}

		Item {
			id: controls

			width: parent.width
			height: Config.mediaButtonGlyphSize
			visible: root.present

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
