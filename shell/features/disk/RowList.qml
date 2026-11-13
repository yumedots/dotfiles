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
	readonly property int step: root.rowHeight + 1
	readonly property var ordered: {
		const list = root.rows.slice();
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
		const want = list.length === 0 ? 0 : Math.ceil(body.height / root.step);

		while (list.length < want)
			list.push({ empty: true, key: "empty" + list.length });

		return list;
	}

	signal toggled(var row)

	function sortBy(key) {
		if (root.sortKey === key)
			root.sortDesc = !root.sortDesc;
		else {
			root.sortKey = key;
			root.sortDesc = key === "size";
		}
	}

	Item {
		id: head

		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: parent.top
		height: 30

		Row {
			anchors.left: parent.left
			anchors.leftMargin: 70
			anchors.verticalCenter: parent.verticalCenter
			spacing: 6

			Text {
				font.family: Config.fontFamily
				font.pixelSize: 11
				color: root.sortKey === "name" ? Config.foreground : Config.dim
				text: "Name"

				MouseArea {
					anchors.fill: parent
					anchors.margins: -6
					onClicked: root.sortBy("name")
				}
			}

			Glyph {
				anchors.verticalCenter: parent.verticalCenter
				visible: root.sortKey === "name"
				glyph: root.sortDesc ? Config.diskIconSortDesc : Config.diskIconSortAsc
				size: 10
				color: Config.foreground
			}
		}

		Row {
			anchors.right: parent.right
			anchors.rightMargin: 14
			anchors.verticalCenter: parent.verticalCenter
			spacing: 6

			Glyph {
				anchors.verticalCenter: parent.verticalCenter
				visible: root.sortKey === "size"
				glyph: root.sortDesc ? Config.diskIconSortDesc : Config.diskIconSortAsc
				size: 10
				color: Config.foreground
			}

			Text {
				font.family: Config.fontFamily
				font.pixelSize: 11
				color: root.sortKey === "size" ? Config.foreground : Config.dim
				text: "Size"

				MouseArea {
					anchors.fill: parent
					anchors.margins: -6
					onClicked: root.sortBy("size")
				}
			}
		}
	}

	Item {
		id: body

		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: head.bottom
		anchors.bottom: parent.bottom
		clip: true

		ListView {
			id: list

			anchors.fill: parent
			model: root.padded
			spacing: 1
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
					const max = Math.max(0, list.contentHeight - list.height);
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
					anchors.verticalCenter: parent.verticalCenter
					width: Math.max(80, (row.width - 140) * 0.38)
					elide: Text.ElideRight
					visible: !row.filler

					font.family: Config.fontFamily
					font.pixelSize: 12
					color: Config.foreground
					text: row.filler ? "" : row.modelData.name
				}

				Text {
					anchors.left: nameText.right
					anchors.leftMargin: 12
					anchors.right: sizeText.left
					anchors.rightMargin: 12
					anchors.verticalCenter: parent.verticalCenter
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

		Scrollbar {
			view: list
			edge: body
		}
	}
}
