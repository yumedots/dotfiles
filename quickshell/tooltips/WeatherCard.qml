import QtQuick
import qs.ui
import qs
import qs.services

Item {
	id: root

	signal closeRequested()

	focus: true

	property bool placeFocus: false
	property bool placeEditing: false
	property string query: ""

	readonly property bool ready: Weather.temp !== ""
	readonly property var temp: Forecast.splitTemp(Weather.temp)
	readonly property string place: Weather.location !== "" ? Weather.location : Weather.place
	readonly property string status: root.ready ? Weather.description : (Weather.status !== "" ? Weather.status : "Loading")
	readonly property var rows: [
		{ label: "Feels like", value: Weather.feels },
		{ label: "Wind", value: Weather.wind },
		{ label: "Humidity", value: Weather.humidity }
	]

	implicitWidth: Config.weatherCardWidth + Config.weatherCardPadding * 2
	implicitHeight: card.implicitHeight + Config.weatherCardPadding * 2

	readonly property real rowStep: suggestProto.implicitHeight + Config.weatherCardSuggestGap
	readonly property int suggestShown: Math.min(suggestList.count, Config.weatherCardSuggestRows)

	function nearestIndex(rows) {
		if (rows.length === 0)
			return -1;

		if (Weather.lat === 0 && Weather.lon === 0)
			return 0;

		let best = 0;
		let bestD = Forecast.geoDistance(Weather.lat, Weather.lon, rows[0].lat, rows[0].lon);

		for (let i = 1; i < rows.length; i++) {
			const d = Forecast.geoDistance(Weather.lat, Weather.lon, rows[i].lat, rows[i].lon);

			if (d < bestD) {
				best = i;
				bestD = d;
			}
		}

		return best;
	}

	function startEdit() {
		root.placeFocus = true;
		root.placeEditing = true;
		root.query = root.place;
		placeInput.forceActiveFocus();
		placeInput.selectAll();
		Qt.callLater(placeInput.selectAll);
	}

	function stopEdit() {
		root.placeEditing = false;
		root.placeFocus = false;
		root.query = "";
		suggestList.reset();
		Weather.search("");
		root.forceActiveFocus();
	}

	function commitPlace() {
		const row = suggestList.current;
		const label = row ? row.label : root.query.trim();

		root.stopEdit();

		if (label !== "")
			Weather.choose(label);
	}

	Keys.onPressed: function (event) {
		if (Input.cancel(event)) {
			if (root.placeEditing)
				root.stopEdit();
			else if (root.placeFocus)
				root.placeFocus = false;
			else
				root.closeRequested();

			event.accepted = true;
			return;
		}

		if (Input.accept(event)) {
			root.startEdit();
			event.accepted = true;
			return;
		}

		if (event.key === Qt.Key_Down)
			root.placeFocus = true;
		else if (event.key === Qt.Key_Up)
			root.placeFocus = false;
	}

	Column {
		id: card

		x: Config.weatherCardPadding
		y: Config.weatherCardPadding
		width: Config.weatherCardWidth
		spacing: Config.weatherCardGap

		Row {
			id: header

			width: card.width
			spacing: Config.weatherCardHeaderGap

			Text {
				id: glyph

				anchors.verticalCenter: parent.verticalCenter
				font.family: Config.fontFamily
				font.pixelSize: Config.weatherCardGlyphSize
				color: Config.foreground
				text: root.ready ? Weather.icon : Config.weatherLoadingIcon
			}

			Column {
				id: info

				anchors.verticalCenter: parent.verticalCenter
				spacing: -2

				Row {
					spacing: 0

					Text {
						font.family: Config.fontFamily
						font.pixelSize: Config.weatherCardTempSize
						color: Config.foreground
						text: root.ready ? root.temp.value : "--"
					}

					Text {
						anchors.bottom: parent.bottom
						anchors.bottomMargin: Config.weatherCardUnitLift
						visible: root.ready && root.temp.unit !== ""
						font.family: Config.fontFamily
						font.pixelSize: Config.weatherCardUnitSize
						color: Config.muted
						text: root.temp.unit
					}
				}

				Text {
					font.family: Config.fontFamily
					font.pixelSize: Config.weatherCardNameSize
					color: Config.foreground
					text: root.status
				}
			}
		}

		Item {
			id: placeRow

			width: card.width
			height: Math.max(placeText.implicitHeight, placeInput.implicitHeight)

			readonly property bool hot: !root.placeEditing && (root.placeFocus || placeHit.containsMouse)

			Highlight {
				active: placeRow.hot
			}

			Text {
				id: placeText

				visible: !root.placeEditing
				width: card.width
				elide: Text.ElideRight

				font.family: Config.fontFamily
				font.pixelSize: Config.weatherCardPlaceSize
				color: placeRow.hot ? Config.launcherHighlightText : Config.muted
				text: root.place
			}

			TextInput {
				id: placeInput

				visible: root.placeEditing
				width: card.width
				selectByMouse: false
				focus: root.placeEditing

				font.family: Config.fontFamily
				font.pixelSize: Config.weatherCardPlaceSize
				color: Config.foreground
				selectionColor: Config.launcherHighlight
				selectedTextColor: Config.launcherHighlightText
				text: root.query

				onTextEdited: {
					root.query = placeInput.text;
					weatherSearch.restart();
				}
				onAccepted: root.commitPlace()
				onActiveFocusChanged: if (activeFocus) selectAll()

				Keys.onPressed: function (event) {
					if (Input.cancel(event)) {
						root.stopEdit();
						event.accepted = true;
						return;
					}

					if (event.key === Qt.Key_Down || event.key === Qt.Key_Up)
						suggestList.handleKey(event);
				}
			}

			MouseArea {
				id: placeHit

				anchors.fill: parent
				hoverEnabled: true
				visible: !root.placeEditing

				onClicked: root.startEdit()
			}
		}

		Item {
			id: suggestBox

			visible: root.placeEditing && root.suggestShown > 0
			width: card.width
			height: root.suggestShown > 0 ? root.suggestShown * root.rowStep - Config.weatherCardSuggestGap : 0

			Selector {
				id: suggestList

				width: parent.width
				visibleRows: Config.weatherCardSuggestRows
				rowHeight: suggestProto.implicitHeight
				rowSpacing: Config.weatherCardSuggestGap
				model: Weather.suggestions

				delegate: Text {
					required property var modelData

					width: ListView.view.rowWidth
					height: ListView.view.rowHeight
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: Config.weatherCardSuggestSize
					color: ListView.isCurrentItem ? Config.launcherHighlightText : Config.foreground
					text: modelData.label
				}
			}
		}

		Rectangle {
			visible: root.ready

			width: card.width
			height: Config.weatherCardDivider
			color: Config.weatherCardDividerColor
		}

		Column {
			width: card.width
			spacing: Config.weatherCardRowGap

			Repeater {
				model: root.rows

				delegate: Row {
					required property var modelData

					width: card.width

					Text {
						width: Config.weatherCardLabelWidth
						font.family: Config.fontFamily
						font.pixelSize: Config.weatherCardRowSize
						color: Config.muted
						text: modelData.label
					}

					Text {
						width: card.width - Config.weatherCardLabelWidth
						horizontalAlignment: Text.AlignRight
						font.family: Config.fontFamily
						font.pixelSize: Config.weatherCardRowSize
						color: Config.foreground
						text: modelData.value
					}
				}
			}
		}
	}

	Text {
		id: suggestProto

		visible: false
		font.family: Config.fontFamily
		font.pixelSize: Config.weatherCardSuggestSize
		text: "0"
	}

	Connections {
		target: Weather

		function onSuggestionsChanged() {
			suggestList.currentIndex = root.nearestIndex(Weather.suggestions);
			suggestList.reset();
		}
	}

	Timer {
		id: weatherSearch

		interval: Config.weatherCardSearchDebounce
		onTriggered: Weather.search(root.query)
	}
}
