pragma ComponentBehavior: Bound

import QtQuick
import qs

Item {
	id: root

	property var items: []
	property var rects: []
	property string selectedPath: ""
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
			color: modelData.item.kind === "dir" ? Config.cpuCore : (modelData.item.kind === "file" ? Config.memoryBase : Config.yellow)
			border.color: root.selectedPath === modelData.item.path ? Config.foreground : Config.surface
			border.width: root.selectedPath === modelData.item.path ? 2 : 1
			opacity: cellMouse.containsMouse ? 0.82 : 1

			Behavior on opacity {
				NumberAnimation { duration: 90 }
			}

			Column {
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.top: parent.top
				anchors.margins: 6
				spacing: 2

				visible: cell.width > 54 && cell.height > 26

				Text {
					width: parent.width
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: 11
					font.weight: Font.Medium
					color: Config.surface
					text: cell.modelData.item.name
				}

				Text {
					width: parent.width
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: 10
					color: Config.surface
					opacity: 0.72
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
