pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.ui

Item {
	id: root

	property var items: []
	property var rects: []
	property var selected: ({})
	signal picked(var item)
	signal activated(var item)

	onWidthChanged: root.recompute()
	onHeightChanged: root.recompute()
	onItemsChanged: root.recompute()

	function recompute() {
		const out = [];
		let total = 0;

		for (let i = 0; i < root.items.length; i++)
			total += Math.max(0, Number(root.items[i].size) || 0);

		if (total <= 0 || root.width <= 0 || root.height <= 0) {
			root.rects = out;
			return;
		}

		let x = 0;
		let y = 0;
		let w = root.width;
		let h = root.height;
		let remaining = total;

		for (let i = 0; i < root.items.length; i++) {
			const item = root.items[i];
			const size = Math.max(0, Number(item.size) || 0);

			if (size <= 0 || remaining <= 0)
				continue;

			const weight = Math.min(1, size / remaining);

			if (w >= h) {
				const rw = w * weight;
				out.push({ x: x, y: y, width: rw, height: h, item: item });
				x += rw;
				w -= rw;
			} else {
				const rh = h * weight;
				out.push({ x: x, y: y, width: w, height: rh, item: item });
				y += rh;
				h -= rh;
			}

			remaining -= size;
		}

		root.rects = out;
	}

	Repeater {
		model: root.rects

		delegate: Rectangle {
			id: cell

			required property var modelData

			x: modelData.x
			y: modelData.y
			width: modelData.width
			height: modelData.height
			readonly property bool checked: root.selected[modelData.item.path] === true

			color: modelData.item.kind === "dir" ? Config.diskDir : (modelData.item.kind === "file" ? Config.diskFile : Config.diskOther)
			border.color: cell.checked ? Config.foreground : Config.surface
			border.width: cell.checked ? 2 : 1
			clip: true
			opacity: cellMouse.containsMouse ? 0.88 : 1

			Behavior on opacity {
				NumberAnimation { duration: 90 }
			}

			Rectangle {
				anchors.top: parent.top
				anchors.right: parent.right
				anchors.margins: 4
				width: 16
				height: 16
				visible: cell.checked
				color: Config.foreground
				border.color: Config.surface
				border.width: 1

				Glyph {
					anchors.centerIn: parent
					glyph: Config.launcherIconActive
					size: 9
					color: Config.surface
				}
			}

			Column {
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.top: parent.top
				anchors.margins: 4
				spacing: 1

				Text {
					width: parent.width
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: 10
					font.weight: Font.Medium
					color: Config.foreground
					text: cell.modelData.item.name
				}

				Text {
					width: parent.width
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: 9
					color: Config.foreground
					opacity: 0.75
					text: cell.modelData.item.sizeText || ""
				}
			}

			MouseArea {
				id: cellMouse

				anchors.fill: parent
				hoverEnabled: true
				onClicked: root.picked(cell.modelData.item)
				onDoubleClicked: root.activated(cell.modelData.item)
			}
		}
	}
}
