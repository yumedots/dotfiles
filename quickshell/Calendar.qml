import QtQuick
import "config.js" as Config
import "helpers.js" as Helpers

Item {
	id: root

	property date today: new Date()
	property int monthOffset: 0
	property int shownDay: 0

	readonly property date first: new Date(root.today.getFullYear(), root.today.getMonth() + root.monthOffset, 1)
	readonly property int days: Helpers.daysInMonth(root.first.getFullYear(), root.first.getMonth())
	readonly property int leading: Helpers.mondayIndex(root.first)
	readonly property int selected: Helpers.clampedDay(root.shownDay || root.today.getDate(), root.first.getFullYear(), root.first.getMonth())
	readonly property date selectedDate: new Date(root.first.getFullYear(), root.first.getMonth(), root.selected)
	readonly property real gridWidth: Config.calendarCellWidth * 7
	readonly property int rows: 6

	implicitWidth: root.gridWidth + Config.calendarPadding * 2
	implicitHeight: Config.calendarPadding * 2 + Config.calendarHeaderHeight + Config.calendarFooterHeight + Config.calendarCellHeight * root.rows

	function step(months) {
		root.monthOffset += months;
		root.shownDay = 0;
	}

	function isToday(day) {
		return root.monthOffset === 0 && day === root.today.getDate();
	}

	component Nav: Item {
		id: nav

		property string glyph
		signal activated()

		implicitWidth: label.implicitWidth + 10
		implicitHeight: Config.calendarHeaderHeight

		Text {
			id: label

			anchors.centerIn: parent
			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: hover.hovered ? Config.foreground : Config.dim
			text: nav.glyph
		}

		HoverHandler {
			id: hover
		}

		MouseArea {
			anchors.fill: parent
			onClicked: nav.activated()
		}
	}

	Item {
		id: header

		anchors.top: parent.top
		anchors.topMargin: Config.calendarPadding
		anchors.horizontalCenter: parent.horizontalCenter
		width: root.gridWidth
		height: Config.calendarHeaderHeight

		Row {
			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			spacing: 2

			Nav {
				glyph: "«"
				onActivated: root.step(-12)
			}

			Nav {
				glyph: "‹"
				onActivated: root.step(-1)
			}
		}

		Row {
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			spacing: 2

			Nav {
				glyph: "›"
				onActivated: root.step(1)
			}

			Nav {
				glyph: "»"
				onActivated: root.step(12)
			}
		}

		Text {
			anchors.centerIn: parent
			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: Config.foreground
			text: Qt.formatDate(root.first, "MMMM yyyy")
		}

		MouseArea {
			anchors.fill: parent
			onClicked: {
				root.monthOffset = 0;
				root.shownDay = 0;
			}
		}
	}

	Row {
		id: weekdays

		anchors.top: header.bottom
		anchors.horizontalCenter: parent.horizontalCenter

		Repeater {
			model: 7

			delegate: Text {
				required property int index

				width: Config.calendarCellWidth
				height: Config.calendarCellHeight
				horizontalAlignment: Text.AlignHCenter
				verticalAlignment: Text.AlignVCenter
				font.family: Config.fontFamily
				font.pixelSize: Config.fontSize
				color: Config.dim
				text: Qt.formatDate(new Date(2024, 0, 1 + index), "ddd")
			}
		}
	}

	Item {
		id: grid

		anchors.top: weekdays.bottom
		anchors.horizontalCenter: parent.horizontalCenter
		width: root.gridWidth
		height: Config.calendarCellHeight * root.rows

		Repeater {
			model: root.rows * 7

			delegate: Item {
				id: cell

				required property int index

				readonly property int day: index - root.leading + 1
				readonly property bool within: cell.day >= 1 && cell.day <= root.days

				x: (cell.index % 7) * Config.calendarCellWidth
				y: Math.floor(cell.index / 7) * Config.calendarCellHeight
				width: Config.calendarCellWidth
				height: Config.calendarCellHeight

				Rectangle {
					anchors.centerIn: parent
					width: Math.min(parent.width, parent.height) - 2
					height: width
					color: Config.foreground
					visible: cell.within && root.isToday(cell.day)
				}

				Text {
					anchors.centerIn: parent
					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: root.isToday(cell.day) ? Config.background : Config.foreground
					text: cell.within ? cell.day : ""
				}

				HoverHandler {
					onHoveredChanged: {
						if (hovered && cell.within)
							root.shownDay = cell.day;
					}
				}
			}
		}
	}

	Item {
		id: footer

		anchors.bottom: parent.bottom
		anchors.bottomMargin: Config.calendarPadding
		anchors.horizontalCenter: parent.horizontalCenter
		width: root.gridWidth
		height: Config.calendarFooterHeight

		Text {
			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: Config.foreground
			text: Qt.formatDate(root.selectedDate, "dddd d MMMM")
		}

		Text {
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: Config.dim
			text: root.days + " days"
		}
	}
}
