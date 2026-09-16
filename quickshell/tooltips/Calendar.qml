import QtQuick
import Quickshell
import qs

Item {
	id: root

	signal closeRequested()

	focus: true

	property date cursor: new Date()
	property date today: clock.date

	readonly property int year: root.cursor.getFullYear()
	readonly property int month: root.cursor.getMonth()
	readonly property int length: Helpers.daysInMonth(root.year, root.month)
	readonly property int leading: Helpers.mondayIndex(new Date(root.year, root.month, 1))
	readonly property int days: Config.calendarRows * 7
	readonly property int previousLength: Helpers.daysInMonth(root.month === 0 ? root.year - 1 : root.year, (root.month + 11) % 12)
	readonly property real gridWidth: Config.calendarCellWidth * 7
	readonly property string monthText: Qt.formatDate(new Date(root.year, root.month, 1), "MMMM")
	readonly property string yearText: String(root.year)

	implicitWidth: root.gridWidth + Config.calendarPadding * 2
	implicitHeight: column.implicitHeight + Config.calendarPadding * 2

	SystemClock {
		id: clock

		precision: SystemClock.Seconds
	}

	function step(days) {
		root.cursor = Helpers.shiftDays(root.cursor, days);
	}

	function stepMonths(months) {
		root.cursor = Helpers.shiftMonths(root.cursor, months);
	}

	function stepYears(years) {
		root.cursor = Helpers.shiftYears(root.cursor, years);
	}

	function isToday(day) {
		return day === root.today.getDate()
			&& root.month === root.today.getMonth()
			&& root.year === root.today.getFullYear();
	}

	function isCursor(day) {
		return day === root.cursor.getDate() && root.month === root.cursor.getMonth()
			&& root.year === root.cursor.getFullYear();
	}

	function dayLabel(index) {
		const day = index - root.leading + 1;

		if (day >= 1 && day <= root.length)
			return String(day);

		return day < 1 ? String(root.previousLength + day) : String(day - root.length);
	}

	Keys.onPressed: function (event) {
		if (event.key === Qt.Key_Escape) {
			root.closeRequested();
		} else if (event.text === "h") {
			root.step(-1);
		} else if (event.text === "l") {
			root.step(1);
		} else if (event.text === "k") {
			root.step(-7);
		} else if (event.text === "j") {
			root.step(7);
		} else if (event.text === "s") {
			root.stepMonths(-1);
		} else if (event.text === "d") {
			root.stepMonths(1);
		} else if (event.text === "a") {
			root.stepYears(-1);
		} else if (event.text === "f") {
			root.stepYears(1);
		} else if (event.text === "r") {
			root.cursor = new Date(root.today);
		} else {
			return;
		}

		event.accepted = true;
	}

	Column {
		id: column

		x: Config.calendarPadding
		y: Config.calendarPadding
		width: root.gridWidth
		spacing: 6

		Rectangle {
			id: box

			width: column.width
			height: boxColumn.implicitHeight + Config.procSearchPadding * 2
			color: Config.launcherSearchBox

			Column {
				id: boxColumn

				anchors.left: parent.left
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				spacing: 2

				Item {
					width: boxColumn.width
					height: Math.max(title.height, arrows.height)

					Row {
						id: title

						x: Config.procSearchPadding
						spacing: 6

						Text {
							id: month

							font.family: Config.fontFamily
							font.pixelSize: Config.fontSize
							color: Config.calendarBase
							text: root.monthText
						}

						Text {
							id: yearLabel

							font.family: Config.fontFamily
							font.pixelSize: Config.fontSize
							color: Config.calendarBase
							text: root.yearText
						}
					}

					Row {
						id: arrows

						anchors.right: parent.right
						anchors.rightMargin: Config.procSearchPadding
						anchors.verticalCenter: parent.verticalCenter
						spacing: Config.calendarArrowGap

						Text {
							font.family: Config.fontFamily
							font.pixelSize: Config.calendarArrowSize
							color: Config.calendarBase
							text: Config.iconPrev
						}

						Text {
							font.family: Config.fontFamily
							font.pixelSize: Config.calendarArrowSize
							color: Config.calendarBase
							text: Config.iconNext
						}
					}
				}

				Row {
					id: weekdays

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
							color: Config.muted
							text: Qt.formatDate(new Date(2024, 0, 1 + index), "ddd")
						}
					}
				}
			}
		}

		Item {
			id: grid

			width: column.width
			height: Config.calendarCellHeight * Config.calendarRows

			Repeater {
				model: root.days

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
						anchors.fill: parent
						visible: cell.inside && root.isToday(cell.day)
						color: Config.calendarTodayBox
					}

					Rectangle {
						anchors.fill: parent
						visible: cell.inside && root.isCursor(cell.day)
						color: "transparent"
						border.width: Config.calendarCursorBorder
						border.color: Config.calendarCursor
					}

					Text {
						anchors.centerIn: parent
						font.family: Config.fontFamily
						font.pixelSize: Config.fontSize
						color: cell.inside ? Config.foreground : Config.dim
						text: root.dayLabel(cell.index)
					}
				}
			}
		}
	}
}
