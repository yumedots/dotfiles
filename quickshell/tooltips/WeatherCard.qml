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

	readonly property var now: Weather.current || {}
	readonly property var rows: Weather.days || []
	readonly property bool loading: root.now.loading === true
	readonly property string savedPlace: String(Weather.places[Weather.index] || "").split(",")[0].trim()
	readonly property string placeName: root.now.place ? root.now.place : root.savedPlace
	readonly property var temp: Format.splitTemp(root.now.temp || "")
	readonly property string tempValue: root.loading || root.temp.value === "" ? "--" : root.temp.value
	readonly property string tempUnit: root.loading ? "" : root.temp.unit
	readonly property var match: root.bestMatch()
	readonly property string ghost: root.ghostText()
	readonly property bool hasGhost: root.editing && root.match !== null && root.ghost !== ""
	readonly property var suggestionRows: root.matchingRows()
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

	onPlaceNameChanged: {
		root.held = true;
		holdTimer.restart();
	}

	function bestMatch() {
		const rows = Weather.suggestions || [];

		if (rows.length === 0 || root.query.trim() === "")
			return null;

		const typed = root.query.trim().toLowerCase();

		for (let i = 0; i < rows.length; i++) {
			if (String(rows[i].label).toLowerCase().indexOf(typed) === 0)
				return rows[i];
		}

		return rows[0];
	}

	function ghostText() {
		const typed = root.query;
		const name = root.match ? String(root.match.name) : "";

		if (typed === "")
			return "";

		return name.toLowerCase().indexOf(typed.toLowerCase()) === 0 ? name.slice(typed.length) : "";
	}

	function matchingRows() {
		const rows = Weather.suggestions || [];
		const typed = root.query.trim().toLowerCase();
		const out = [];

		if (rows.length === 0)
			return out;

		if (typed === "")
			return rows.slice(0, 5);

		for (let i = 0; i < rows.length && out.length < 5; i++) {
			if (String(rows[i].label).toLowerCase().indexOf(typed) === 0)
				out.push(rows[i]);
		}

		if (out.length === 0)
			out.push(rows[0]);

		return out;
	}

	function regionOf(row) {
		const label = String(row.label || "");
		const name = String(row.name || "");

		if (name === "" || label.indexOf(name) !== 0)
			return "";

		return label.slice(name.length).replace(/^,\s*/, "");
	}

	function dayTempText(row) {
		return Format.splitTemp(row.tempMax).value + "° " + Format.splitTemp(row.tempMin).value + "°";
	}

	function syncSuggest() {
		const typed = root.query.trim().toLowerCase();
		const label = root.match ? String(root.match.label).toLowerCase() : "";

		if (typed === "") {
			if ((Weather.suggestions || []).length > 0)
				Weather.search("");

			return;
		}

		if (label.indexOf(typed) === 0)
			return;

		if (typed.length < 2) {
			weatherSearch.stop();
			return;
		}

		weatherSearch.restart();
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
		Weather.search("");
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

			Text {
				id: leftArrow

				visible: !root.editing
				anchors.left: placeText.right
				anchors.leftMargin: Config.weatherCardHeaderGap
				anchors.verticalCenter: parent.verticalCenter
				height: placeMetrics.height
				opacity: root.headerShown ? 1 : 0
				font.family: Config.fontFamily
				font.pixelSize: Config.weatherPlaceSize
				color: leftHit.containsMouse ? Config.foreground : Config.muted
				text: Config.weatherIconLeft

				Behavior on opacity {
					NumberAnimation {
						duration: Config.popupFadeMs
					}
				}

				MouseArea {
					id: leftHit

					anchors.fill: parent
					anchors.margins: -4
					hoverEnabled: true
					enabled: root.headerShown
					onClicked: Weather.shift(-1)
				}
			}

			Text {
				id: rightArrow

				visible: !root.editing
				anchors.left: leftArrow.right
				anchors.leftMargin: Config.weatherCardHeaderGap
				anchors.verticalCenter: parent.verticalCenter
				height: placeMetrics.height
				opacity: root.headerShown ? 1 : 0
				font.family: Config.fontFamily
				font.pixelSize: Config.weatherPlaceSize
				color: rightHit.containsMouse ? Config.foreground : Config.muted
				text: Config.weatherIconRight

				Behavior on opacity {
					NumberAnimation {
						duration: Config.popupFadeMs
					}
				}

				MouseArea {
					id: rightHit

					anchors.fill: parent
					anchors.margins: -4
					hoverEnabled: true
					enabled: root.headerShown
					onClicked: Weather.shift(1)
				}
			}

			Text {
				id: addIcon

				visible: !root.editing
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				height: placeMetrics.height
				opacity: root.headerShown ? 1 : 0
				font.family: Config.fontFamily
				font.pixelSize: Config.weatherPlaceSize
				color: addHit.containsMouse ? Config.foreground : Config.muted
				text: Config.weatherIconAdd

				Behavior on opacity {
					NumberAnimation {
						duration: Config.popupFadeMs
					}
				}

				MouseArea {
					id: addHit

					anchors.fill: parent
					anchors.margins: -4
					hoverEnabled: true
					enabled: root.headerShown
					onClicked: root.startEdit("", true)
				}
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
						root.syncSuggest();
					}
					onActiveFocusChanged: if (activeFocus) selectAll()

					Keys.onPressed: function (event) {
						if (Input.cancel(event)) {
							root.stopEdit();
							event.accepted = true;
							return;
						}

						if (Input.accept(event)) {
							root.commitPlace();
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
								? Format.weatherCodeInfo(dayCell.row.code, Config.weatherCodes, Config.weatherIcon).glyph
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
							text: dayCell.row ? root.dayTempText(dayCell.row) : ""
						}
					}
				}
			}
		}
	}

	Item {
		id: overlay

		x: Config.weatherCardPadding
		y: Config.weatherCardPadding + header.height + Config.weatherCardGap
		width: Config.weatherCardWidth
		height: card.height - header.height - Config.weatherCardGap
		visible: root.editing
		z: 10

		Rectangle {
			anchors.fill: parent
			color: Config.surface
		}

		Column {
			id: suggestList

			anchors.left: parent.left
			anchors.right: parent.right
			anchors.top: parent.top
			spacing: 0

			Repeater {
				model: root.suggestionRows

				delegate: Item {
					id: suggestRow

					required property var modelData

					width: suggestList.width
					height: suggestMetrics.height

					Text {
						id: suggestName

						anchors.left: parent.left
						anchors.verticalCenter: parent.verticalCenter
						width: Math.min(implicitWidth, suggestRow.width * 0.55)
						height: suggestMetrics.height
						elide: Text.ElideRight
						font.family: Config.fontFamily
						font.pixelSize: Config.weatherPlaceSize
						color: suggestHit.containsMouse ? Config.foreground : Config.foreground
						text: String(suggestRow.modelData.name || "")
					}

					Text {
						anchors.left: suggestName.right
						anchors.leftMargin: 8
						anchors.right: parent.right
						anchors.rightMargin: 8
						anchors.verticalCenter: parent.verticalCenter
						height: suggestMetrics.height
						elide: Text.ElideRight
						font.family: Config.fontFamily
						font.pixelSize: Config.weatherPlaceSize
						color: Config.muted
						text: root.regionOf(suggestRow.modelData)
					}

					MouseArea {
						id: suggestHit

						anchors.fill: parent
						hoverEnabled: true
						onClicked: root.pick(suggestRow.modelData)
					}
				}
			}
		}
	}

	Timer {
		id: weatherSearch

		interval: Config.weatherCardSearchDebounce
		onTriggered: Weather.search(root.query)
	}

	Timer {
		id: holdTimer

		interval: 1800
		onTriggered: root.held = false
	}
}
