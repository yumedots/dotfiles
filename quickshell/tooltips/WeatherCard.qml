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
	property bool selectQuery: false
	property int queryStamp: 0

	readonly property bool ready: Weather.temp !== ""
	readonly property var temp: Forecast.splitTemp(Weather.temp)
	readonly property string place: (Weather.location !== "" ? Weather.location : Weather.place).split(",")[0].trim()
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

	function pushQuery(select) {
		root.selectQuery = select;
		root.queryStamp = root.queryStamp + 1;
	}

	function startEdit(value) {
		root.placeFocus = true;
		root.placeEditing = true;
		root.query = value !== undefined && value !== "" ? value : root.place;
		root.pushQuery(true);
	}

	function stopEdit() {
		root.placeEditing = false;
		root.placeFocus = false;
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
		const label = root.query.trim();
		const exact = root.match !== null && String(root.match.name).toLowerCase() === label.toLowerCase();

		root.stopEdit();

		if (label !== "")
			Weather.choose(label, exact ? root.match.lat : 0, exact ? root.match.lon : 0);
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
		else if (!root.placeEditing && Input.direction(event) === "right") {
			Weather.shift(1);
			event.accepted = true;
		} else if (!root.placeEditing && Input.direction(event) === "left") {
			Weather.shift(-1);
			event.accepted = true;
		}
	}

	Column {
		id: card

		x: Config.weatherCardPadding
		y: Config.weatherCardPadding
		width: Config.weatherCardWidth
		spacing: Config.weatherCardGap

		Item {
			id: placeRow

			width: card.width
			height: placeText.implicitHeight


			Row {
				id: placeText

				width: card.width - Config.weatherCardPlacePad
				spacing: Config.weatherCardGap
				clip: true

				Repeater {
					id: placeRepeater

					model: Weather.places

					Row {
						id: entry

						readonly property var slot: Weather.slot(index)
						readonly property bool current: index === Weather.index
						readonly property color ink: entry.current || hover.hovered ? Config.foreground : Config.muted

						spacing: Config.weatherCardHeaderGap

						Text {
							anchors.verticalCenter: parent.verticalCenter
							font.family: Config.fontFamily
							width: Config.weatherCardRowGlyphSize
							horizontalAlignment: Text.AlignLeft
							font.pixelSize: Config.weatherCardRowGlyphSize
							color: entry.ink
							text: entry.slot ? entry.slot.icon : Config.weatherLoadingIcon
						}

						Column {
							id: nameColumn
							width: Config.weatherCardRowTextWidth

							anchors.verticalCenter: parent.verticalCenter
							spacing: -2

							Row {
								spacing: 0
								width: Config.weatherCardRowTextWidth

								Text {
									font.family: Config.fontFamily
									font.pixelSize: Config.weatherCardRowTempSize
									color: entry.ink
									text: entry.slot && entry.slot.temp !== "" ? Forecast.splitTemp(entry.slot.temp).value : "--"
								}

								Text {
									anchors.bottom: parent.bottom
									anchors.bottomMargin: Config.weatherCardUnitLift
									visible: entry.slot && entry.slot.temp !== ""
									font.family: Config.fontFamily
									font.pixelSize: Config.weatherCardRowUnitSize
									color: entry.ink
									text: entry.slot ? Forecast.splitTemp(entry.slot.temp).unit : ""
								}
							}

							Text {
								font.family: Config.fontFamily
								font.pixelSize: Config.weatherCardPlaceSize
								color: entry.ink
								width: Config.weatherCardRowTextWidth
								elide: Text.ElideRight
								text: entry.slot && entry.slot.description !== "" ? entry.slot.description : " "
							}

							Item {
								id: nameLine

								width: Config.weatherCardRowTextWidth
								height: nameText.implicitHeight

								Text {
									id: nameText

									anchors.fill: parent
									visible: !(entry.current && root.placeEditing)
									font.family: Config.fontFamily
									font.pixelSize: Config.weatherCardPlaceSize
									color: entry.ink
									elide: Text.ElideRight
									text: (modelData || "").split(",")[0].trim()
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

									visible: entry.current && root.hasGhost
									x: queryMeasure.implicitWidth
									width: Math.max(0, nameLine.width - queryMeasure.implicitWidth)
									elide: Text.ElideRight
									anchors.verticalCenter: parent.verticalCenter

									font.family: Config.fontFamily
									font.pixelSize: Config.weatherCardPlaceSize
									color: Config.muted
									text: root.ghost
								}

								TextInput {
									id: nameInput

									anchors.fill: parent
									visible: entry.current && root.placeEditing
									focus: entry.current && root.placeEditing
									clip: true
									selectByMouse: false

									font.family: Config.fontFamily
									font.pixelSize: Config.weatherCardPlaceSize
									color: Config.foreground
									selectionColor: Config.launcherHighlight
									selectedTextColor: Config.launcherHighlightText
									text: root.query

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
										if (!entry.current)
											return;

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

						HoverHandler {
							id: hover
						}

						TapHandler {
							onTapped: {
								if (!current)
									Weather.shift(index - Weather.index);

								root.startEdit((modelData || "").split(",")[0].trim());
							}
						}
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

}
