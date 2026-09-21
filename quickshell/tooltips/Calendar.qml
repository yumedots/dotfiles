import QtQuick
import Quickshell
import qs.ui
import qs.services
import qs

Item {
	id: root

	signal closeRequested()

	focus: true

	property date cursor: new Date()
	property date today: clock.date
	property int weekStart: Config.calendarWeekStart

	readonly property string cursorKey: Helpers.dateKey(root.cursor)
	readonly property string todayKey: Helpers.dateKey(root.today)
	readonly property var grid: Helpers.monthGrid(root.cursor.getFullYear(), root.cursor.getMonth(), root.weekStart, root.todayKey, root.cursorKey, Config.calendarRows)
	readonly property var weekdays: Helpers.weekdayLabels(root.weekStart)
	readonly property var meters: root.buildMeters()
	readonly property real gridWidth: Config.calendarCellWidth * 7
	readonly property real gridLeft: Config.calendarMeterColumn + Config.calendarColumnGap * 2 + Config.calendarSeparator
	readonly property string monthText: Qt.formatDate(new Date(root.cursor.getFullYear(), root.cursor.getMonth(), 1), "MMMM")
	readonly property string yearText: String(root.cursor.getFullYear())
	readonly property bool hasWeather: Weather.temp !== ""
	readonly property string weatherName: Weather.description
	readonly property string weatherPlace: Weather.location === "" ? Weather.description : Weather.location
	readonly property var weatherTemp: Helpers.splitTemp(Weather.temp)
	readonly property real mondayInk: (Config.calendarCellWidth - weekdayMetrics.width) / 2 + weekdayMetrics.tightBoundingRect.x
	readonly property real titleX: root.gridLeft + root.mondayInk - monthMetrics.tightBoundingRect.x
	readonly property real gridTop: Config.calendarCellHeight + calendar.spacing
	readonly property real meterTop: root.gridTop + Math.max(0, Config.calendarRows - root.meters.length) * Config.calendarCellHeight
	readonly property real placeTop: (Config.calendarCellHeight - weatherPlace.height) / 2

	implicitWidth: card.implicitWidth + Config.calendarPadding * 2
	implicitHeight: card.implicitHeight + Config.calendarPadding * 2

	SystemClock {
		id: clock

		precision: SystemClock.Seconds
	}

	TextMetrics {
		id: monthMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.calendarMonthSize
		text: root.monthText
	}

	TextMetrics {
		id: weekdayMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.calendarWeekdaySize
		text: root.weekdays.length > 0 ? root.weekdays[0] : ""
	}

	function buildMeters() {
		const out = [
			{ icon: Config.calendarIconDay, label: "DAY", pct: Helpers.progressPercent(Helpers.dayProgress(root.today)) },
			{ icon: Config.calendarIconMonth, label: "MONTH", pct: Helpers.progressPercent(Helpers.monthProgress(root.today)) },
			{ icon: Config.calendarIconYear, label: "YEAR", pct: Helpers.progressPercent(Helpers.yearProgress(root.today)) }
		];

		if (Config.calendarBirthYear > 0)
			out.push({ icon: Config.calendarIconLife, label: "LIFE", pct: Helpers.progressPercent(Helpers.lifeProgress(Config.calendarBirthYear, Config.calendarLifeExpectancy, root.today.getFullYear())) });

		return out;
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

	Keys.onPressed: function (event) {
		Input.calendar(event, root);
	}

	Column {
		id: card

		x: Config.calendarPadding
		y: Config.calendarPadding
		spacing: Config.calendarHeaderGap

		Item {
			id: box

			width: row.width
			height: boxColumn.implicitHeight + Config.procSearchPadding * 2

			Column {
				id: boxColumn

				anchors.left: parent.left
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				spacing: 2

				Item {
					id: titleRow

					width: boxColumn.width
					height: Math.max(title.height, weatherNow.height, arrows.height)

					Row {
						id: title

						x: root.titleX
						anchors.verticalCenter: parent.verticalCenter
						spacing: Config.calendarArrowGap

						Text {
							id: month

							font.family: Config.fontFamily
							font.pixelSize: Config.calendarMonthSize
							color: Config.calendarBase
							text: root.monthText
						}

						Text {
							id: yearLabel

							font.family: Config.fontFamily
							font.pixelSize: Config.calendarMonthSize
							color: Config.calendarBase
							text: root.yearText
						}
					}

					Row {
						id: weatherNow

						x: 0
						anchors.verticalCenter: parent.verticalCenter
						spacing: Config.calendarWeatherGap

						Text {
							font.family: Config.fontFamily
							font.pixelSize: Config.calendarWeatherSize
							color: root.hasWeather ? Config.foreground : Config.muted
							text: root.hasWeather ? Weather.icon : Config.weatherLoadingIcon
						}

						Row {
							visible: root.hasWeather
							spacing: 0

							Text {
								font.family: Config.fontFamily
								font.pixelSize: Config.calendarMonthSize
								color: Config.foreground
								text: root.weatherTemp.value
							}

							Text {
								visible: root.weatherTemp.unit !== ""
								font.family: Config.fontFamily
								font.pixelSize: Config.calendarWeatherUnitSize
								color: Config.foreground
								text: root.weatherTemp.unit
							}
						}

						Text {
							visible: root.hasWeather && root.weatherName !== ""

							width: Math.min(implicitWidth, Config.calendarWeatherNameWidth)
							elide: Text.ElideRight
							font.family: Config.fontFamily
							font.pixelSize: Config.calendarWeatherNameSize
							color: Config.foreground
							text: root.weatherName
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
			}
		}

		Row {
			id: row

			spacing: Config.calendarColumnGap

			Item {
				id: meterColumn

				width: Config.calendarMeterColumn
				height: calendar.height

				Repeater {
					model: root.meters

					delegate: Item {
						required property var modelData
						required property int index

						width: meterColumn.width
						height: Config.calendarMeterRow
						y: root.meterTop + index * Config.calendarCellHeight + (Config.calendarCellHeight - height) / 2

						Text {
							id: meterLabel

							anchors.verticalCenter: parent.verticalCenter
							width: Config.calendarMeterLabelWidth
							font.family: Config.fontFamily
							font.pixelSize: Config.fontSize
							color: Config.foreground
							text: modelData.icon + " " + modelData.label
						}

						Text {
							id: meterValue

							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							width: Config.calendarMeterValueWidth
							horizontalAlignment: Text.AlignRight
							font.family: Config.fontFamily
							font.pixelSize: Config.fontSize
							color: Config.foreground
							text: modelData.pct + "%"
						}

						Rectangle {
							id: meterTrack

							anchors.left: meterLabel.right
							anchors.right: meterValue.left
							anchors.verticalCenter: parent.verticalCenter
							height: Config.calendarMeterHeight
							color: Config.calendarTrack

							Rectangle {
								width: Math.round(parent.width * modelData.pct / 100)
								height: parent.height
								color: Config.foreground
							}
						}
					}
				}

				Item {
					id: placeRow

					width: meterColumn.width
					height: weatherPlace.height
					y: root.placeTop

					Text {
						id: weatherPlace

						x: 0
						visible: root.weatherPlace !== ""
						font.family: Config.fontFamily
						font.pixelSize: Config.calendarWeekdaySize
						color: Config.foreground
						text: root.weatherPlace
					}
				}
			}

			Rectangle {
				width: Config.calendarSeparator
				height: calendar.height
				color: Config.calendarSeparatorColor
			}

			Column {
				id: calendar

				width: root.gridWidth
				spacing: 6

				Row {
					id: weekdays

					Repeater {
						model: root.weekdays

						delegate: Text {
							required property string modelData

							width: Config.calendarCellWidth
							height: Config.calendarCellHeight
							horizontalAlignment: Text.AlignHCenter
							verticalAlignment: Text.AlignVCenter
							font.family: Config.fontFamily
							font.pixelSize: Config.calendarWeekdaySize
							color: Config.foreground
							text: modelData
						}
					}
				}

				Item {
					id: days

					width: calendar.width
					height: Config.calendarCellHeight * Config.calendarRows

					Repeater {
						model: Config.calendarRows * 7

						delegate: Item {
							id: cell

							required property int index

							readonly property var day: root.grid[Math.floor(cell.index / 7)][cell.index % 7]

							x: (cell.index % 7) * Config.calendarCellWidth
							y: Math.floor(cell.index / 7) * Config.calendarCellHeight
							width: Config.calendarCellWidth
							height: Config.calendarCellHeight

							Rectangle {
								anchors.fill: parent
								visible: cell.day.today
								color: Config.calendarTodayBox
							}

							Rectangle {
								anchors.fill: parent
								visible: cell.day.cursor
								color: "transparent"
								border.width: Config.calendarCursorBorder
								border.color: Config.calendarCursor
							}

							Text {
								anchors.centerIn: parent
								font.family: Config.fontFamily
								font.pixelSize: Config.fontSize
								color: cell.day.inMonth || cell.day.today || cell.day.cursor ? Config.foreground : Config.calendarOutside
								text: cell.day.day
							}
						}
					}
				}
			}
		}
	}
}
