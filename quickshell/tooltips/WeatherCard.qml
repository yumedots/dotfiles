import QtQuick
import qs.ui
import qs
import qs.services

Item {
	id: root

	signal closeRequested()

	focus: true

	property bool editing: false
	property bool adding: false
	property bool held: false
	property string query: ""
	property bool selectQuery: false
	property int queryStamp: 0
	property int pickIndex: 0

	readonly property var now: Weather.current || {}
	readonly property var rows: Weather.days || []
	readonly property bool loading: root.now.loading === true
	readonly property string savedPlace: String(Weather.places[Weather.index] || "").split(",")[0].trim()
	readonly property string placeName: root.now.place ? root.now.place : root.savedPlace
	readonly property string tempValue: root.loading || !root.now.tempValue ? "--" : root.now.tempValue
	readonly property string tempUnit: root.loading || !root.now.tempUnit ? "" : root.now.tempUnit
	readonly property var match: root.suggestionRows.length > 0 ? root.suggestionRows[0] : null
	readonly property string ghost: Weather.ghost
	readonly property bool hasGhost: root.editing && root.match !== null && root.ghost !== ""
	readonly property var suggestionRows: Weather.matches
	readonly property bool headerShown: root.editing || root.held || heroHover.hovered || headerHover.hovered
	readonly property int dayCount: root.rows.length > 0 ? Math.min(root.rows.length, 7) : 7
	readonly property real dayTextWidth: dayTempMetrics.width * 1.04 + 2
	readonly property real dayCellWidth: Math.max(1, Math.min(
		Math.max(root.dayTextWidth, dayLabelMetrics.width, Config.weatherDayGlyphSize),
		(card.width - Config.weatherDayGap * (root.dayCount - 1)) / root.dayCount))
	readonly property real dayTempPixel: root.dayCellWidth >= root.dayTextWidth
		? Config.weatherDayTempSize
		: Math.max(8, Math.floor(Config.weatherDayTempSize * (root.dayCellWidth - 2) / root.dayTextWidth))
	readonly property real placeMaxWidth: card.width - leftArrow.width - rightArrow.width - addIcon.width - Config.weatherCardHeaderGap * 3
	readonly property real statWidth: (card.width - heroGlyphMetrics.width - Config.weatherCardGap * 4 - heroTempMetrics.width - heroUnitMetrics.width) / 3
	readonly property real dayHeight: dayGlyphMetrics.height + Config.weatherDayGap * 2 + dayLabelMetrics.height + dayTempMetrics.height

	implicitWidth: Config.weatherCardWidth + Config.weatherCardPadding * 2
	implicitHeight: card.implicitHeight + Config.weatherCardPadding * 2

	onQueryChanged: {
		root.pickIndex = 0;
		Weather.query(root.query);
	}
	onSuggestionRowsChanged: root.pickIndex = Calc.clamp(root.pickIndex, 0, Math.max(0, root.suggestionRows.length - 1))

	onPlaceNameChanged: {
		root.held = true;
		holdTimer.restart();
	}

	function pickRow(step) {
		const rows = root.suggestionRows;

		if (rows.length === 0)
			return;

		root.pickIndex = Calc.clamp(root.pickIndex + step, 0, rows.length - 1);
	}

	function takeChosen() {
		const rows = root.suggestionRows;

		if (rows.length === 0) {
			root.commitPlace();
			return;
		}

		root.pick(rows[Calc.clamp(root.pickIndex, 0, rows.length - 1)]);
	}

	function pushQuery(select) {
		root.selectQuery = select;
		root.queryStamp = root.queryStamp + 1;
	}

	function startEdit(value, adding) {
		root.editing = true;
		root.adding = adding === true;
		root.query = value !== undefined && value !== "" ? value : "";
		root.pushQuery(true);
	}

	function stopEdit() {
		root.editing = false;
		root.adding = false;
		root.query = "";
		root.forceActiveFocus();
	}

	function completeGhost() {
		if (!root.hasGhost)
			return;

		root.query = String(root.match.name);
		root.pushQuery(false);
	}

	function commitPlace() {
		const row = root.match;

		if (row === null || String(row.label || "").trim() === "")
			return;

		const label = String(row.label);
		const adding = root.adding;

		root.stopEdit();

		if (adding)
			Weather.add(label, row.lat, row.lon);
		else
			Weather.choose(label, row.lat, row.lon);
	}

	function pick(row) {
		const label = String(row.label || row.name || "");
		const adding = root.adding;

		root.stopEdit();

		if (label === "")
			return;

		if (adding)
			Weather.add(label, row.lat, row.lon);
		else
			Weather.choose(label, row.lat, row.lon);
	}

	Keys.onPressed: function (event) {
		if (Input.cancel(event)) {
			if (root.editing)
				root.stopEdit();
			else
				root.closeRequested();

			event.accepted = true;
			return;
		}

		if (Input.accept(event) && !root.editing) {
			root.startEdit(root.placeName);
			event.accepted = true;
			return;
		}

		if (root.editing)
			return;

		if (Input.direction(event) === "right") {
			Weather.shift(1);
			event.accepted = true;
		} else if (Input.direction(event) === "left") {
			Weather.shift(-1);
			event.accepted = true;
		}
	}

	TextMetrics {
		id: placeMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.weatherPlaceSize
		text: "Placeholder"
	}

	TextMetrics {
		id: heroGlyphMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.weatherHeroGlyphSize
		text: ""
	}

	TextMetrics {
		id: heroTempMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.weatherHeroTempSize
		text: "-00"
	}

	TextMetrics {
		id: heroUnitMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.weatherHeroUnitSize
		text: "°C"
	}

	TextMetrics {
		id: heroTempInk

		font.family: Config.fontFamily
		font.pixelSize: Config.weatherHeroTempSize
		text: root.tempValue
	}

	TextMetrics {
		id: heroUnitInk

		font.family: Config.fontFamily
		font.pixelSize: Config.weatherHeroUnitSize
		text: String(root.tempUnit).replace("°", "")
	}

	TextMetrics {
		id: heroLabelMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.weatherHeroLabelSize
		text: "FEELS"
	}

	TextMetrics {
		id: heroValueMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.weatherHeroValueSize
		text: "00 km/h"
	}

	TextMetrics {
		id: dayGlyphMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.weatherDayGlyphSize
		text: ""
	}

	TextMetrics {
		id: dayLabelMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.weatherDayLabelSize
		text: "WED"
	}

	TextMetrics {
		id: dayTempMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.weatherDayTempSize
		text: "00° 00°"
	}

	TextMetrics {
		id: suggestMetrics

		font.family: Config.fontFamily
		font.pixelSize: Config.weatherPlaceSize
		text: "Region"
	}

	Column {
		id: card

		x: Config.weatherCardPadding
		y: Config.weatherCardPadding
		width: Config.weatherCardWidth
		spacing: Config.weatherCardGap

		Item {
			id: header

			width: card.width
			height: placeMetrics.height

			HoverHandler {
				id: headerHover
			}

			Text {
				id: placeText

				visible: !root.editing
				anchors.left: parent.left
				anchors.verticalCenter: parent.verticalCenter
				width: Math.min(implicitWidth, root.placeMaxWidth)
				height: placeMetrics.height
				elide: Text.ElideRight
				font.family: Config.fontFamily
				font.pixelSize: Config.weatherPlaceSize
				color: placeHit.containsMouse ? Config.foreground : Config.muted
				text: root.placeName

				MouseArea {
					id: placeHit

					anchors.fill: parent
					anchors.margins: -4
					hoverEnabled: true
					onClicked: root.startEdit(root.placeName)
				}
			}

			RevealIcon {
				id: leftArrow

				visible: !root.editing
				anchors.left: placeText.right
				anchors.leftMargin: Config.weatherCardHeaderGap
				anchors.verticalCenter: parent.verticalCenter
				height: placeMetrics.height
				shown: root.headerShown
				font.pixelSize: Config.weatherPlaceSize
				text: Config.weatherIconLeft
				onClicked: Weather.shift(-1)
			}

			RevealIcon {
				id: rightArrow

				visible: !root.editing
				anchors.left: leftArrow.right
				anchors.leftMargin: Config.weatherCardHeaderGap
				anchors.verticalCenter: parent.verticalCenter
				height: placeMetrics.height
				shown: root.headerShown
				font.pixelSize: Config.weatherPlaceSize
				text: Config.weatherIconRight
				onClicked: Weather.shift(1)
			}

			RevealIcon {
				id: addIcon

				visible: !root.editing
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				height: placeMetrics.height
				shown: root.headerShown
				font.pixelSize: Config.weatherPlaceSize
				text: Config.weatherIconAdd
				onClicked: root.startEdit("", true)
			}

			Item {
				id: inputBox

				visible: root.editing
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				height: placeMetrics.height

				Text {
					id: queryMeasure

					visible: false
					font.family: Config.fontFamily
					font.pixelSize: Config.weatherPlaceSize
					text: root.query
				}

				Text {
					id: ghostText

					visible: root.hasGhost
					x: queryMeasure.implicitWidth
					anchors.verticalCenter: parent.verticalCenter
					width: Math.max(0, inputBox.width - queryMeasure.implicitWidth)
					height: placeMetrics.height
					elide: Text.ElideRight
					font.family: Config.fontFamily
					font.pixelSize: Config.weatherPlaceSize
					color: Config.muted
					text: root.ghost
				}

				TextInput {
					id: nameInput

					anchors.fill: parent
					focus: root.editing
					clip: true
					selectByMouse: false

					font.family: Config.fontFamily
					font.pixelSize: Config.weatherPlaceSize
					color: Config.foreground
					selectionColor: Config.launcherHighlight
					selectedTextColor: Config.launcherHighlightText

					onTextEdited: {
						root.query = nameInput.text;
					}
					onActiveFocusChanged: if (activeFocus) selectAll()

					Keys.onPressed: function (event) {
						if (Input.cancel(event)) {
							root.stopEdit();
							event.accepted = true;
							return;
						}

						if (Input.accept(event)) {
							root.takeChosen();
							event.accepted = true;
							return;
						}

						if (event.key === Qt.Key_Down) {
							root.pickRow(1);
							event.accepted = true;
							return;
						}

						if (event.key === Qt.Key_Up) {
							root.pickRow(-1);
							event.accepted = true;
							return;
						}

						if (event.key === Qt.Key_Tab) {
							root.completeGhost();
							event.accepted = true;
						}
					}
				}

				Connections {
					target: root

					function onQueryStampChanged() {
						nameInput.text = root.query;

						if (root.selectQuery) {
							root.selectQuery = false;
							nameInput.selectAll();
						} else
							nameInput.cursorPosition = nameInput.text.length;
					}
				}
			}
		}

		Repeater {
			model: root.editing ? root.suggestionRows : []

			delegate: Item {
				id: suggestRow

				required property var modelData
				required property int index

				readonly property bool chosen: suggestRow.index === root.pickIndex

				width: card.width
				height: suggestMetrics.height + Config.weatherCardGap

				Highlight {
					active: suggestRow.chosen || suggestHit.containsMouse
				}

				Text {
					id: suggestName

					anchors.left: parent.left
					anchors.leftMargin: Config.weatherCardGap
					anchors.verticalCenter: parent.verticalCenter
					width: Math.min(implicitWidth, suggestRow.width * 0.55)
					elide: Text.ElideRight
					font.family: Config.fontFamily
					font.pixelSize: Config.weatherPlaceSize
					color: suggestRow.chosen || suggestHit.containsMouse ? Config.launcherHighlightText : Config.foreground
					text: String(suggestRow.modelData.name || "")
				}

				Text {
					anchors.left: suggestName.right
					anchors.leftMargin: Config.weatherCardGap
					anchors.right: parent.right
					anchors.rightMargin: Config.weatherCardGap
					anchors.verticalCenter: parent.verticalCenter
					elide: Text.ElideRight
					font.family: Config.fontFamily
					font.pixelSize: Config.weatherPlaceSize
					color: suggestRow.chosen || suggestHit.containsMouse ? Config.launcherHighlightText : Config.muted
					text: suggestRow.modelData.region
				}

				MouseArea {
					id: suggestHit

					anchors.fill: parent
					hoverEnabled: true

					onEntered: root.pickIndex = suggestRow.index
					onClicked: root.pick(suggestRow.modelData)
				}
			}
		}

		Item {
			id: hero

			width: card.width
			height: tempBox.height

			HoverHandler {
				id: heroHover
			}

			Text {
				id: heroGlyph

				anchors.left: parent.left
				anchors.bottom: parent.bottom
				height: heroGlyphMetrics.height
				font.family: Config.fontFamily
				font.pixelSize: Config.weatherHeroGlyphSize
				color: Config.foreground
				text: root.loading ? Config.weatherLoadingIcon : (root.now.icon ? root.now.icon : Config.weatherIcon)
			}

			Item {
				id: tempBox

				anchors.left: heroGlyph.right
				anchors.leftMargin: Config.weatherCardGap
				width: tempNumber.width + tempUnitText.width + 2
				height: tempNumber.height + Config.weatherHeroUnitTop

				Text {
					id: tempNumber

					anchors.left: parent.left
					anchors.bottom: parent.bottom
					height: heroTempMetrics.height
					font.family: Config.fontFamily
					font.pixelSize: Config.weatherHeroTempSize
					color: Config.foreground
					text: root.tempValue
				}

				Text {
					id: tempUnitText

					anchors.left: tempNumber.right
					anchors.top: tempNumber.top
					anchors.topMargin: (heroTempInk.tightBoundingRect.y - heroTempInk.boundingRect.y)
						- (heroUnitInk.tightBoundingRect.y - heroUnitInk.boundingRect.y)
					height: heroUnitMetrics.height
					font.family: Config.fontFamily
					font.pixelSize: Config.weatherHeroUnitSize
					color: Config.foreground
					text: root.tempUnit
				}
			}

			Item {
				id: stats

				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				width: root.statWidth * 3 + Config.weatherCardGap * 2
				height: statRow.height

				Row {
					id: statRow

					spacing: Config.weatherCardGap

					Column {
						width: root.statWidth
						spacing: 3

						Text {
							width: parent.width
							height: heroLabelMetrics.height
							font.family: Config.fontFamily
							font.pixelSize: Config.weatherHeroLabelSize
							color: Config.muted
							text: "FEELS"
						}

						Text {
							width: parent.width
							height: heroValueMetrics.height
							elide: Text.ElideRight
							font.family: Config.fontFamily
							font.pixelSize: Config.weatherHeroValueSize
							color: Config.foreground
							text: root.now.feels ? root.now.feels : "--"
						}
					}

					Column {
						width: root.statWidth
						spacing: 3

						Text {
							width: parent.width
							height: heroLabelMetrics.height
							font.family: Config.fontFamily
							font.pixelSize: Config.weatherHeroLabelSize
							color: Config.muted
							text: "WIND"
						}

						Text {
							width: parent.width
							height: heroValueMetrics.height
							elide: Text.ElideRight
							font.family: Config.fontFamily
							font.pixelSize: Config.weatherHeroValueSize
							color: Config.foreground
							text: root.now.wind ? root.now.wind : "--"
						}
					}

					Column {
						width: root.statWidth
						spacing: 3

						Text {
							width: parent.width
							height: heroLabelMetrics.height
							font.family: Config.fontFamily
							font.pixelSize: Config.weatherHeroLabelSize
							color: Config.muted
							text: "HUMID"
						}

						Text {
							width: parent.width
							height: heroValueMetrics.height
							elide: Text.ElideRight
							font.family: Config.fontFamily
							font.pixelSize: Config.weatherHeroValueSize
							color: Config.foreground
							text: root.now.humidity ? root.now.humidity : "--"
						}
					}
				}
			}
		}

		Rectangle {
			id: separator

			width: card.width
			height: Config.weatherSeparator
			color: Config.weatherSeparatorColor
		}

		Item {
			id: daysSection

			width: card.width
			height: root.dayHeight

			Row {
				id: daysRow

				spacing: Config.weatherDayGap

				Repeater {
					model: root.dayCount

					delegate: Item {
						id: dayCell

						required property int index

						readonly property var row: dayCell.index < root.rows.length ? root.rows[dayCell.index] : null

						width: root.dayCellWidth
						height: root.dayHeight

						Text {
							id: dayGlyph

							anchors.horizontalCenter: parent.horizontalCenter
							anchors.top: parent.top
							height: dayGlyphMetrics.height
							font.family: Config.fontFamily
							font.pixelSize: Config.weatherDayGlyphSize
							color: Config.foreground
							text: dayCell.row
								? (dayCell.row.glyph || Config.weatherIcon)
								: Config.weatherLoadingIcon
						}

						Text {
							id: dayLabel

							anchors.horizontalCenter: parent.horizontalCenter
							anchors.top: dayGlyph.bottom
							anchors.topMargin: Config.weatherDayGap
							height: dayLabelMetrics.height
							font.family: Config.fontFamily
							font.pixelSize: Config.weatherDayLabelSize
							color: Config.muted
							text: dayCell.row ? dayCell.row.day : ""
						}

						Text {
							id: dayTemps

							anchors.horizontalCenter: parent.horizontalCenter
							anchors.top: dayLabel.bottom
							anchors.topMargin: Config.weatherDayGap
							width: parent.width
							height: dayTempMetrics.height
							horizontalAlignment: Text.AlignHCenter
							elide: Text.ElideRight
							font.family: Config.fontFamily
							font.pixelSize: root.dayTempPixel
							color: Config.foreground
							text: dayCell.row ? dayCell.row.temps : ""
						}
					}
				}
			}
		}

	}


	Timer {
		id: holdTimer

		interval: 1800
		onTriggered: root.held = false
	}
}
