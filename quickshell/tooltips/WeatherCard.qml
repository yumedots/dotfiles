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

	implicitWidth: Config.weatherCardWidth + Config.weatherCardPadding * 2
	implicitHeight: card.implicitHeight + Config.weatherCardPadding * 2

	function bestMatch() {
		const rows = Weather.suggestions;

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

	function syncSuggest() {
		const typed = root.query.trim().toLowerCase();
		const label = root.match ? String(root.match.label).toLowerCase() : "";

		if (typed === "") {
			if (Weather.suggestions.length > 0)
				Weather.search("");

			return;
		}

		if (label.indexOf(typed) === 0)
			return;

		weatherSearch.restart();
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
		if (root.hasGhost)
			root.query = String(root.match.name);
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
				width: card.width - Config.weatherCardPlacePad
				elide: Text.ElideRight

				font.family: Config.fontFamily
				font.pixelSize: Config.weatherCardPlaceSize
				color: placeRow.hot ? Config.launcherHighlightText : Config.muted
				text: root.place
			}

			TextInput {
				id: placeInput

				visible: root.placeEditing
				width: card.width - Config.weatherCardPlacePad
				clip: true
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

			Text {
				id: queryMeasure

				visible: false
				font.family: Config.fontFamily
				font.pixelSize: Config.weatherCardPlaceSize
				text: root.query
			}

			Text {
				id: ghost

				visible: root.hasGhost
				x: queryMeasure.implicitWidth
				width: Math.max(0, card.width - Config.weatherCardPlacePad - queryMeasure.implicitWidth)
				elide: Text.ElideRight
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
