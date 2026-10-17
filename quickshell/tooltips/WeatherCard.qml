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
	readonly property var match: root.bestMatch()
	readonly property bool hasGhost: root.placeEditing && root.match !== null && root.ghost !== ""
	readonly property string ghost: root.ghostText()
	readonly property bool ghostFits: root.hasGhost && queryMetrics.advanceWidth + ghostMetrics.advanceWidth <= Config.weatherCardWidth

	implicitWidth: Config.weatherCardWidth + Config.weatherCardPadding * 2
	implicitHeight: card.implicitHeight + Config.weatherCardPadding * 2

	function bestMatch() {
		const rows = Weather.suggestions;

		if (rows.length === 0 || root.query.trim() === "")
			return null;

		let best = 0;

		if (Weather.lat !== 0 || Weather.lon !== 0) {
			let bestD = Forecast.geoDistance(Weather.lat, Weather.lon, rows[0].lat, rows[0].lon);

			for (let i = 1; i < rows.length; i++) {
				const d = Forecast.geoDistance(Weather.lat, Weather.lon, rows[i].lat, rows[i].lon);

				if (d < bestD) {
					best = i;
					bestD = d;
				}
			}
		}

		return rows[best];
	}

	function ghostText() {
		const typed = root.query.trim().toLowerCase();
		const label = root.match ? String(root.match.label) : "";

		return label.toLowerCase().indexOf(typed) === 0 ? label.slice(typed.length) : "";
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
		Weather.search("");
		root.forceActiveFocus();
	}

	function completeGhost() {
		if (root.match)
			root.query = root.match.label;
	}

	function commitPlace() {
		const label = root.query.trim();

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

		if (Input.accept(event) && !root.placeEditing) {
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

			TextMetrics {
				id: queryMetrics

				font.family: Config.fontFamily
				font.pixelSize: Config.weatherCardPlaceSize
				text: root.query
			}

			TextMetrics {
				id: ghostMetrics

				font.family: Config.fontFamily
				font.pixelSize: Config.weatherCardPlaceSize
				text: root.ghost
			}

			Text {
				id: ghost

				visible: root.ghostFits
				x: queryMetrics.advanceWidth
				anchors.verticalCenter: placeInput.verticalCenter

				font.family: Config.fontFamily
				font.pixelSize: Config.weatherCardPlaceSize
				color: Config.muted
				text: root.ghost
			}

			MouseArea {
				id: placeHit

				anchors.fill: parent
				hoverEnabled: true
				visible: !root.placeEditing

				onClicked: root.startEdit()
			}
		}
	}

	Timer {
		id: weatherSearch

		interval: Config.weatherCardSearchDebounce
		onTriggered: Weather.search(root.query)
	}
}
