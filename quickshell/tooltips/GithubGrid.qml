import QtQuick
import qs.ui
import qs.services
import qs

Item {
	id: root

	signal closeRequested()
	signal refreshRequested()

	focus: true

	readonly property var cells: Github.grid
	readonly property int weeks: Config.contribWeeks
	readonly property color accentInk: Helpers.pick(Config.mono, Config.contribBase, Config.contribBaseMono)

	implicitWidth: Config.contribTooltipWidth + Config.contribTooltipPadding * 2
	implicitHeight: column.implicitHeight + Config.contribTooltipPadding * 2

	onVisibleChanged: {
		if (root.visible)
			Github.refresh(false);
	}

	function cellColor(value) {
		if (!value || !value.level)
			return Config.contribEmpty;

		return Helpers.mixColors(Config.contribEmpty, root.accentInk, Math.min(4, value.level) / 4);
	}

	function statusLine() {
		if (Github.login === "")
			return Github.status !== "" ? Github.status : "looking for your GitHub user";

		return "@" + Github.login;
	}

	Keys.onPressed: function (event) {
		if (event.key === Qt.Key_Escape) {
			root.closeRequested();
			event.accepted = true;
		} else if (event.text === "r") {
			root.refreshRequested();
			event.accepted = true;
		}
	}

	Column {
		id: column

		x: Config.contribTooltipPadding
		y: Config.contribTooltipPadding
		width: Config.contribTooltipWidth
		spacing: 6

		Item {
			id: person

			width: column.width
			height: Math.max(slot.height, who.implicitHeight, year.implicitHeight)

			Rectangle {
				id: slot

				width: Config.contribAvatar
				height: Config.contribAvatar
				color: Config.launcherSearchBox
				clip: true

				Text {
					anchors.centerIn: parent
					visible: avatar.status !== Image.Ready
					font.family: Config.fontFamily
					font.pixelSize: Math.round(slot.height * 0.6)
					color: root.accentInk
					text: Config.iconGithub
				}

				Image {
					id: avatar

					anchors.fill: parent
					source: Github.login !== "" ? "https://github.com/" + Github.login + ".png" : ""
					fillMode: Image.PreserveAspectCrop
					visible: status === Image.Ready
				}
			}

			Text {
				id: who

				anchors.left: slot.right
				anchors.leftMargin: Config.notifySlotGap
				anchors.verticalCenter: parent.verticalCenter
				width: Math.max(0, person.width - slot.width - year.width - Config.notifySlotGap * 2)
				elide: Text.ElideRight
				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
				color: root.accentInk
				text: root.statusLine()
			}

			Text {
				id: year

				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
				color: root.accentInk
				text: Github.total > 0 ? Github.total + " this year" : ""
			}

		}

		Item {
			id: legend

			readonly property int step: Config.contribCell + Config.contribGap
			readonly property int base: Math.ceil((less.implicitWidth + Config.contribGap) / legend.step)

			width: column.width
			height: Config.contribCell

			Text {
				id: less

				x: 0
				anchors.verticalCenter: parent.verticalCenter
				font.family: Config.fontFamily
				font.pixelSize: Config.notifyAppFontSize
				color: Config.muted
				text: "less"
			}

			Repeater {
				model: 5

				delegate: Rectangle {
					required property int index

					x: (legend.base + index) * legend.step
					anchors.verticalCenter: parent.verticalCenter
					width: Config.contribCell
					height: Config.contribCell
					color: root.cellColor({ level: index })
				}
			}

			Text {
				id: more

				x: (legend.base + 5) * legend.step
				anchors.verticalCenter: parent.verticalCenter
				font.family: Config.fontFamily
				font.pixelSize: Config.notifyAppFontSize
				color: Config.muted
				text: "more"
			}
		}

		CellGrid {
			id: grid

			values: root.cells
			columns: root.weeks
			cellSize: Config.contribCell
			gap: Config.contribGap
			colorFor: function (value) { return root.cellColor(value); }
		}

		Text {
			width: column.width
			font.family: Config.fontFamily
			font.pixelSize: Config.notifyAppFontSize
			color: Config.muted
			text: Github.loading ? "refreshing..." : (Github.fetched > 0 ? "updated " + Qt.formatDateTime(new Date(Github.fetched), "MMM d h:mm AP") + " · r to refresh" : "r to fetch")
		}
	}
}
