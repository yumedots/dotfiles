pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.ui

Item {
	id: root

	property var rows: []
	property var selected: ({})
	property string glyph: ""
	property string sortKey: "size"
	property bool sortDesc: true
	readonly property int rowHeight: 34
	readonly property int step: root.rowHeight
	readonly property var ordered: {
		const needle = search.text.trim().toLowerCase();
		const list = root.rows.filter(function (r) {
			return needle === "" || (String(r.name) + " " + String(r.detail)).toLowerCase().indexOf(needle) >= 0;
		});
		const key = root.sortKey;
		const dir = root.sortDesc ? -1 : 1;

		list.sort(function (a, b) {
			if (key === "name")
				return dir * String(a.name).localeCompare(String(b.name));

			return dir * ((Number(a.size) || 0) - (Number(b.size) || 0));
		});

		return list;
	}
	readonly property var padded: {
		const list = root.ordered.slice();
		const want = list.length === 0 ? 0 : Math.floor((body.height + 1) / root.step);

		while (list.length < want)
			list.push({ empty: true, key: "empty" + list.length });

		return list;
	}

	signal toggled(var row)

	onOrderedChanged: {
		glide.stop();
		list.contentY = 0;
	}

	function sortBy(key) {
		if (root.sortKey === key)
			root.sortDesc = !root.sortDesc;
		else {
			root.sortKey = key;
			root.sortDesc = key === "size";
		}
	}

	SearchField {
		id: search

		anchors.left: parent.left
		anchors.leftMargin: 14
		anchors.right: sorts.left
		anchors.rightMargin: 10
		anchors.top: parent.top
		anchors.topMargin: 14
		height: 34
		size: 12
		padding: 12
		corner: 0
		textOffset: 2
		placeholder: "Search"
		typing: true
	}

	Row {
		id: sorts

		anchors.right: parent.right
		anchors.rightMargin: 14
		anchors.verticalCenter: search.verticalCenter
		spacing: 8

		Repeater {
			model: [["Name", "name"], ["Size", "size"]]

			delegate: Rectangle {
				id: chip

				required property var modelData

				readonly property bool active: root.sortKey === chip.modelData[1]

				width: chipRow.width + 24
				height: 34
				radius: 0
				color: chip.active ? Config.launcherHighlight : Config.launcherSearchBox

				Row {
					id: chipRow

					anchors.centerIn: parent
					spacing: 6

					Text {
						anchors.verticalCenter: parent.verticalCenter

						font.family: Config.fontFamily
						font.pixelSize: 12
						color: chip.active ? Config.foreground : Config.dim
						text: chip.modelData[0]
					}

					Glyph {
						anchors.verticalCenter: parent.verticalCenter
						visible: chip.active
						glyph: root.sortDesc ? Config.diskIconSortDesc : Config.diskIconSortAsc
						size: 10
						color: Config.foreground
					}
				}

				MouseArea {
					anchors.fill: parent
					onClicked: root.sortBy(chip.modelData[1])
				}
			}
		}
	}

	MouseArea {
		anchors.fill: search
		z: 5
		onPressed: function (mouse) {
			search.focusInput();
			mouse.accepted = false;
		}
	}

	Component.onCompleted: search.focusInput()

	Item {
		id: body

		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: search.bottom
		anchors.topMargin: 14
		anchors.bottom: parent.bottom
		clip: true

		ListView {
			id: list

			anchors.fill: parent
			model: root.padded
			spacing: 0
			interactive: false
			boundsBehavior: Flickable.StopAtBounds

			NumberAnimation {
				id: glide

				target: list
				property: "contentY"
				duration: 130
				easing.type: Easing.OutCubic
			}

			WheelHandler {
				acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
				onWheel: function (event) {
					const max = list.contentHeight - list.height;

					if (max < 2)
						return;

					const base = Math.round(list.contentY / root.step) * root.step;
					const next = Math.max(0, Math.min(max, base + (event.angleDelta.y > 0 ? -1 : 1) * root.step));

					glide.stop();
					glide.to = next;
					glide.start();
				}
			}

			delegate: Item {
				id: row

				required property var modelData
				required property int index

				readonly property bool filler: row.modelData.empty === true
				readonly property bool checked: !row.filler && root.selected[row.modelData.key] !== undefined

				width: list.width
				height: root.rowHeight

				Rectangle {
					anchors.fill: parent
					color: row.index % 2 === 0 ? Config.surface : Config.launcherSearchBox
					opacity: rowHover.containsMouse && !row.filler ? 1 : 0.72
				}

				MouseArea {
					id: rowHover

					anchors.fill: parent
					hoverEnabled: true
					enabled: !row.filler
					onClicked: root.toggled(row.modelData)
				}

				Check {
					id: mark

					anchors.left: parent.left
					anchors.leftMargin: 10
					anchors.verticalCenter: parent.verticalCenter
					visible: !row.filler
					checked: row.checked
					onToggled: root.toggled(row.modelData)
				}

				Glyph {
					id: rowIcon

					anchors.left: mark.right
					anchors.leftMargin: 12
					anchors.verticalCenter: parent.verticalCenter
					visible: !row.filler
					glyph: root.glyph
					size: 14
					color: Config.foreground
				}

				Text {
					id: nameText

					anchors.left: rowIcon.right
					anchors.leftMargin: 12
					anchors.right: detailText.left
					anchors.rightMargin: 16
					anchors.verticalCenter: parent.verticalCenter
					elide: Text.ElideRight
					visible: !row.filler

					font.family: Config.fontFamily
					font.pixelSize: 12
					color: Config.foreground
					text: row.filler ? "" : row.modelData.name
				}

				Text {
					id: detailText

					anchors.right: sizeText.left
					anchors.rightMargin: 16
					anchors.verticalCenter: parent.verticalCenter
					width: row.width * 0.34
					elide: Text.ElideMiddle
					visible: !row.filler

					font.family: Config.fontFamily
					font.pixelSize: 11
					color: Config.dim
					text: row.filler ? "" : row.modelData.detail
				}

				Text {
					id: sizeText

					anchors.right: parent.right
					anchors.rightMargin: 14
					anchors.verticalCenter: parent.verticalCenter
					width: 78
					horizontalAlignment: Text.AlignRight
					elide: Text.ElideRight
					visible: !row.filler

					font.family: Config.fontFamily
					font.pixelSize: 11
					color: Config.foreground
					text: row.filler ? "" : row.modelData.sizeText
				}
			}
		}

	}
}
