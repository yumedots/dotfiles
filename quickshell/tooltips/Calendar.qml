import QtQuick
import qs

Item {
	id: root

	property date today: new Date()
	property int monthOffset: 0

	readonly property date first: new Date(root.today.getFullYear(), root.today.getMonth() + root.monthOffset, 1)
	readonly property int year: root.first.getFullYear()
	readonly property int month: root.first.getMonth()
	readonly property int length: Helpers.daysInMonth(root.year, root.month)
	readonly property int leading: Helpers.mondayIndex(root.first)
	readonly property int rows: Math.ceil((root.leading + root.length) / 7)
	readonly property real gridWidth: Config.calendarCellWidth * 7

	implicitWidth: root.gridWidth + Config.calendarPadding * 2
	implicitHeight: Config.calendarPadding * 2
		+ Config.calendarHeaderHeight
		+ Config.calendarCellHeight
		+ Config.calendarCellHeight * root.rows

	function shift(months) {
		root.monthOffset += months;
	}

	function reset() {
		root.monthOffset = 0;
	}

	function isToday(day) {
		return root.monthOffset === 0 && day === root.today.getDate();
	}

	component Arrow: Item {
		id: arrow

		property string glyph
		signal fired()

		implicitWidth: label.implicitWidth + 10
		implicitHeight: Config.calendarHeaderHeight

		Text {
			id: label

			anchors.centerIn: parent
			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: Config.foreground
			text: arrow.glyph
		}

		TapHandler {
			onTapped: arrow.fired()
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

			Arrow {
				glyph: "«"
				onFired: root.shift(-12)
			}

			Arrow {
				glyph: "‹"
				onFired: root.shift(-1)
			}
		}

		Row {
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			spacing: 2

			Arrow {
				glyph: "›"
				onFired: root.shift(1)
			}

			Arrow {
				glyph: "»"
				onFired: root.shift(12)
			}
		}

		Text {
			anchors.centerIn: parent
			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: Config.foreground
			text: Qt.formatDate(root.first, "MMMM yyyy")

			TapHandler {
				onTapped: root.reset()
			}
		}
	}

	Rectangle {
		anchors.top: header.top
		anchors.bottom: weekdays.bottom
		anchors.left: header.left
		anchors.right: header.right
		color: "transparent"
		border.width: 1
		border.color: Config.foreground
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
				color: Config.foreground
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

				readonly property int day: cell.index - root.leading + 1
				readonly property bool inside: cell.day >= 1 && cell.day <= root.length

				x: (cell.index % 7) * Config.calendarCellWidth
				y: Math.floor(cell.index / 7) * Config.calendarCellHeight
				width: Config.calendarCellWidth
				height: Config.calendarCellHeight

				Rectangle {
					anchors.centerIn: parent
					width: Math.min(parent.width, parent.height) - 2
					height: width
					color: Config.foreground
					visible: cell.inside && root.isToday(cell.day)
				}

				Text {
					anchors.centerIn: parent
					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: root.isToday(cell.day) ? Config.background : Config.foreground
					text: cell.inside ? cell.day : ""
				}
			}
		}
	}
}
