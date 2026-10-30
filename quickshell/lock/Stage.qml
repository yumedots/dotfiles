import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.ui

PanelWindow {
	id: root

	required property var modelData
	property var source
	property string wallpaper: ""
	property string saver: "none"
	property string account: ""
	property bool power: true
	property var actions: []
	property bool menuOpen: false

	signal powerRequested()
	signal actionPicked(var action)

	readonly property string mode: root.source ? root.source.mode : "locked"
	readonly property string message: root.source ? root.source.message : ""
	readonly property bool open: root.mode === "open"

	readonly property real inset: Math.min(Config.lockInset, Math.round(root.width * 0.1))
	readonly property real headTop: Math.max(root.inset, Math.round(root.height * 0.08))
	readonly property real clockSize: Math.round(Math.min(root.width * 0.082, root.height * 0.15))
	readonly property real promptGap: Math.round(root.height * 0.06)

	property real intro: 0
	property real cardIntro: 0
	property real veil: 1
	property real screenFade: 1

	screen: root.modelData

	anchors.top: true
	anchors.left: true
	anchors.bottom: true
	anchors.right: true

	implicitWidth: root.screen ? root.screen.width : 1
	implicitHeight: root.screen ? root.screen.height : 1

	exclusiveZone: -1
	color: "transparent"

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "lock"
	WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
	WlrLayershell.focusable: true

	visible: true

	Component.onCompleted: Qt.callLater(root.grab)

	function grab() {
		surface.forceActiveFocus();
	}

	SequentialAnimation {
		running: true

		NumberAnimation { target: root; property: "intro"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
	}

	SequentialAnimation {
		running: true

		PauseAnimation { duration: 120 }
		NumberAnimation { target: root; property: "cardIntro"; from: 0; to: 1; duration: 380; easing.type: Easing.OutCubic }
	}

	SequentialAnimation {
		id: leave

		running: root.open

		PauseAnimation { duration: 550 }
		NumberAnimation { target: root; property: "veil"; to: 0; duration: 320; easing.type: Easing.OutCubic }
		NumberAnimation { target: root; property: "screenFade"; to: 0; duration: 320; easing.type: Easing.OutCubic }
	}

	Item {
		id: surface

		anchors.fill: parent
		focus: true
		opacity: root.screenFade

		Rectangle {
			anchors.fill: parent
			color: Config.surface
		}

		Item {
			id: backdrop

			anchors.fill: parent
			clip: true

			Image {
				id: art

				anchors.fill: parent
				source: root.wallpaper === "" ? "" : "file://" + root.wallpaper
				fillMode: Image.PreserveAspectCrop
				asynchronous: true
				cache: true
				opacity: art.status === Image.Ready ? 1 : 0
				scale: 1

				Behavior on opacity {
					NumberAnimation { duration: Config.wallpaperTransitionMs; easing.type: Easing.OutCubic }
				}

				SequentialAnimation on scale {
					running: root.saver === "drift"
					loops: Animation.Infinite

					NumberAnimation { to: 1.1; duration: 42000; easing.type: Easing.InOutSine }
					NumberAnimation { to: 1.03; duration: 42000; easing.type: Easing.InOutSine }
				}
			}
		}

		Rectangle {
			id: scrim

			anchors.fill: parent
			color: Config.surface
			opacity: Config.lockScrim * root.veil
		}

		ScreenSaver {
			anchors.fill: parent
			name: root.saver
		}

		MouseArea {
			anchors.fill: parent
			onPressed: root.grab()
		}

		Column {
			id: heading

			x: root.inset
			y: root.headTop + (1 - root.intro) * 16
			opacity: root.intro * root.veil
			spacing: 5

			Text {
				id: clock

				font.family: Config.fontFamily
				font.pixelSize: root.clockSize
				font.weight: Font.Medium
				font.letterSpacing: -root.clockSize * 0.032
				color: Config.foreground
				text: Qt.formatDateTime(stamp.date, Config.lockClockFormat)
			}

			Text {
				font.family: Config.fontFamily
				font.pixelSize: Config.lockDateSize
				color: Config.foreground
				opacity: 0.72
				text: Qt.formatDateTime(stamp.date, Config.lockDateFormat)
			}

			Text {
				visible: root.account !== ""
				font.family: Config.fontFamily
				font.pixelSize: Config.lockDateSize
				color: Config.foreground
				opacity: 0.62
				text: root.account
			}

			SystemClock {
				id: stamp

				precision: SystemClock.Minutes
			}
		}

		HyprBorder {
			id: card

			x: root.inset
			y: heading.y + heading.height + root.promptGap + (1 - root.cardIntro) * 14
			width: row.implicitWidth + card.inset * 2
			height: row.implicitHeight + card.inset * 2
			padding: Config.lockCardPadding
			backgroundColor: Config.surfaceTranslucent
			opacity: root.cardIntro * root.veil

			Behavior on width {
				NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
			}

			Row {
				id: row

				spacing: Config.lockIconGap

				Text {
					id: mark

					anchors.verticalCenter: parent.verticalCenter
					font.family: Config.fontFamily
					font.pixelSize: Config.lockIconSize
					color: root.mode === "wrong" ? Config.red : (root.open ? Config.powerBase : Config.foreground)
					opacity: root.mode === "checking" ? 0.4 : 1
					text: root.open ? Config.lockOpenIcon : Config.lockIcon

					Behavior on opacity {
						NumberAnimation { duration: 140 }
					}

					Behavior on color {
						ColorAnimation { duration: 200 }
					}
				}

				GlyphStrip {
					id: strip

					count: Math.min(Config.lockBoxes, Math.max(1, filled + 1))
					filled: root.source ? root.source.filled : 0
					pool: Config.lockGlyphPool
					glyphs: true
				}
			}
		}

		Text {
			id: note

			x: root.inset
			y: card.y + card.height + 10
			font.family: Config.fontFamily
			font.pixelSize: Config.lockNoteSize
			color: Config.red
			opacity: root.message === "" ? 0 : 1
			text: root.message

			Behavior on opacity {
				NumberAnimation { duration: 160 }
			}
		}

		Rectangle {
			id: powerButton

			visible: root.power
			x: root.inset
			y: root.height - root.inset - powerButton.height
			width: 40
			height: 40
			radius: 2
			color: powerHit.containsMouse ? Config.launcherHighlight : Config.surfaceTranslucent
			opacity: root.intro * root.veil

			Text {
				anchors.centerIn: parent
				font.family: Config.fontFamily
				font.pixelSize: Config.lockPowerSize
				color: Config.foreground
				opacity: powerHit.containsMouse ? 1 : 0.62
				text: Config.lockPowerIcon

				Behavior on opacity {
					NumberAnimation { duration: 120 }
				}
			}

			MouseArea {
				id: powerHit

				anchors.fill: parent
				hoverEnabled: true
				onClicked: {
					if (root.actions.length > 0)
						root.menuOpen = !root.menuOpen;
					else
						root.powerRequested();
				}
			}
		}

		MouseArea {
			anchors.fill: parent
			visible: root.menuOpen
			onClicked: root.menuOpen = false
		}

		HyprBorder {
			id: powerMenu

			visible: root.menuOpen
			x: root.inset
			y: powerButton.y - height - 10
			width: actionColumn.implicitWidth + powerMenu.inset * 2
			height: actionColumn.implicitHeight + powerMenu.inset * 2
			padding: 6
			backgroundColor: Config.surfaceTranslucent

			Column {
				id: actionColumn

				spacing: 0

				Repeater {
					model: root.actions

					delegate: Rectangle {
						id: actionRow

						required property var modelData

						width: actionLabel.implicitWidth + 58
						height: 34
						radius: 2
						color: actionHit.containsMouse ? Config.launcherHighlight : "transparent"

						Text {
							anchors.left: parent.left
							anchors.leftMargin: 12
							anchors.verticalCenter: parent.verticalCenter
							font.family: Config.fontFamily
							font.pixelSize: 16
							color: Config.foreground
							text: actionRow.modelData.glyph || ""
						}

						Text {
							id: actionLabel

							anchors.left: parent.left
							anchors.leftMargin: 40
							anchors.verticalCenter: parent.verticalCenter
							font.family: Config.fontFamily
							font.pixelSize: Config.lockPowerSize
							color: Config.foreground
							text: actionRow.modelData.name || ""
						}

						MouseArea {
							id: actionHit

							anchors.fill: parent
							hoverEnabled: true
							onClicked: {
								root.menuOpen = false;
								root.actionPicked(actionRow.modelData);
							}
						}
					}
				}
			}
		}

		Keys.onPressed: function (event) {
			if (root.source === null)
				return;

			if (event.key === Qt.Key_Escape) {
				if (root.menuOpen)
					root.menuOpen = false;
				else
					root.source.dismiss();

				event.accepted = true;
				return;
			}

			if (event.key === Qt.Key_Backspace) {
				root.source.back();
				event.accepted = true;
				return;
			}

			if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
				root.source.submit();
				event.accepted = true;
				return;
			}

			if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
				return;

			if (event.text.length > 0 && event.text.charCodeAt(0) >= 0x20) {
				root.source.type(event.text);
				event.accepted = true;
			}
		}
	}

	onModeChanged: {
		if (root.mode === "wrong")
			strip.reject();
	}
}
