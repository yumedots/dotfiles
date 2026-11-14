pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.ui

Item {
	id: root

	property var items: []
	property var selected: ({})
	property var bubbles: []
	readonly property var palette: [Config.memoryBase, Config.cpuBase, Config.cpuCore, Config.yellow, Config.weatherBase, Config.red]

	signal activated(var item)
	signal toggled(var item)

	onWidthChanged: if (root.bubbles.length === 0) root.pack()
	onHeightChanged: if (root.bubbles.length === 0) root.pack()
	onItemsChanged: root.pack()

	function pack() {
		const list = [];

		for (let i = 0; i < root.items.length && list.length < 40; i++) {
			if ((Number(root.items[i].size) || 0) > 0)
				list.push(root.items[i]);
		}

		if (list.length === 0 || root.width < 10 || root.height < 10) {
			root.bubbles = [];
			return;
		}

		const big = Math.pow(Number(list[0].size), 0.3);
		const placed = [];
		const aspect = Math.min(1.8, Math.max(1, root.width / root.height));

		for (let i = 0; i < list.length; i++) {
			const r = Math.max(0.3, Math.pow(Number(list[i].size), 0.3) / big) * 100;
			let x = 0;
			let y = 0;
			let found = i === 0;

			for (let d = 0; !found && d < 1600; d += 3) {
				const steps = Math.max(12, Math.floor(d / 4));

				for (let k = 0; k < steps; k++) {
					const a = (k / steps) * Math.PI * 2;
					const cx = Math.cos(a) * d * aspect;
					const cy = Math.sin(a) * d;
					let ok = true;

					for (let j = 0; j < placed.length; j++) {
						const dx = cx - placed[j].x;
						const dy = cy - placed[j].y;
						const gap = r + placed[j].r + 6;

						if (dx * dx + dy * dy < gap * gap) {
							ok = false;
							break;
						}
					}

					if (ok) {
						x = cx;
						y = cy;
						found = true;
						break;
					}
				}
			}

			placed.push({ x: x, y: y, r: r, item: list[i] });
		}

		let minX = Infinity;
		let maxX = -Infinity;
		let minY = Infinity;
		let maxY = -Infinity;

		for (let i = 0; i < placed.length; i++) {
			minX = Math.min(minX, placed[i].x - placed[i].r);
			maxX = Math.max(maxX, placed[i].x + placed[i].r);
			minY = Math.min(minY, placed[i].y - placed[i].r);
			maxY = Math.max(maxY, placed[i].y + placed[i].r);
		}

		root.bounds = { minX: minX, maxX: maxX, minY: minY, maxY: maxY };
		root.bubbles = placed;
	}

	property var bounds: ({ minX: 0, maxX: 1, minY: 0, maxY: 1 })
	readonly property real fitScale: {
		const b = root.bounds;
		const cap = root.bubbles.length === 1 ? Math.min(root.width, root.height) * 0.3 / root.bubbles[0].r : Infinity;
		return Math.max(0.01, Math.min(cap, (root.width - 16) / (b.maxX - b.minX), (root.height - 16) / (b.maxY - b.minY)));
	}
	readonly property real offX: (root.width - (root.bounds.maxX - root.bounds.minX) * root.fitScale) / 2 - root.bounds.minX * root.fitScale
	readonly property real offY: (root.height - (root.bounds.maxY - root.bounds.minY) * root.fitScale) / 2 - root.bounds.minY * root.fitScale

	Repeater {
		model: root.bubbles

		delegate: Item {
			id: bubble

			required property var modelData
			required property int index

			readonly property bool checked: root.selected[bubble.modelData.item.path] !== undefined
			readonly property bool isDir: bubble.modelData.item.kind === "dir"
			readonly property color tint: bubble.isDir ? root.palette[bubble.index % root.palette.length] : Config.foreground
			readonly property real r: bubble.modelData.r * root.fitScale

			x: bubble.modelData.x * root.fitScale + root.offX - bubble.r
			y: bubble.modelData.y * root.fitScale + root.offY - bubble.r
			width: bubble.r * 2
			height: bubble.r * 2
			property real pop: 0

			scale: bubble.pop
			opacity: Math.min(1, bubble.pop * 1.6)

			SequentialAnimation on pop {
				PauseAnimation { duration: bubble.index * 32 }
				NumberAnimation { from: 0; to: 1; duration: 420; easing.type: root.bubbles.length === 1 ? Easing.OutCubic : Easing.OutBack; easing.overshoot: 2.2 }
			}

			Rectangle {
				anchors.fill: parent
				radius: width / 2
				color: bubble.checked ? bubble.tint : Qt.alpha(bubble.tint, bubbleMouse.containsMouse ? 0.42 : 0.2)
			}

			MouseArea {
				id: bubbleMouse

				anchors.fill: parent
				hoverEnabled: true
				onClicked: if (bubble.isDir) root.activated(bubble.modelData.item)
			}

			Column {
				anchors.centerIn: parent
				width: bubble.width * 0.88
				spacing: 2

				Glyph {
					anchors.horizontalCenter: parent.horizontalCenter
					visible: bubble.r >= 55
					glyph: bubble.isDir ? Config.diskIconDir : Config.diskIconFile
					size: Math.min(26, bubble.r * 0.34)
					color: bubble.checked ? Config.surface : bubble.tint
				}

				Item {
					width: parent.width
					height: nameText.height

					Glyph {
						id: inlineIcon

						anchors.left: nameText.left
						anchors.leftMargin: -width - 4
						anchors.verticalCenter: parent.verticalCenter
						visible: bubble.r < 55
						glyph: bubble.isDir ? Config.diskIconDir : Config.diskIconFile
						size: nameText.font.pixelSize
						color: bubble.checked ? Config.surface : bubble.tint
					}

					Text {
						id: nameText

						anchors.horizontalCenter: parent.horizontalCenter
						anchors.horizontalCenterOffset: inlineIcon.visible ? (inlineIcon.width + 4) / 2 : 0
						width: Math.min(implicitWidth, parent.width - (inlineIcon.visible ? inlineIcon.width + 4 : 0))
						horizontalAlignment: Text.AlignHCenter
						elide: Text.ElideMiddle

						font.family: Config.fontFamily
						font.pixelSize: Math.max(10, Math.min(20, bubble.r * 0.26))
						font.weight: Font.Medium
						color: bubble.checked ? Config.surface : Config.foreground
						text: bubble.modelData.item.name
					}
				}

				Text {
					width: parent.width
					horizontalAlignment: Text.AlignHCenter
					elide: Text.ElideRight
					visible: bubble.r > 30

					font.family: Config.fontFamily
					font.pixelSize: Math.max(9, Math.min(15, bubble.r * 0.2))
					color: bubble.checked ? Config.surface : bubble.tint
					text: bubble.modelData.item.sizeText || ""
				}
			}

			Check {
				x: bubble.r + bubble.r * 0.7071 - width / 2
				y: bubble.r - bubble.r * 0.7071 - height / 2
				checked: bubble.checked
				onToggled: root.toggled(bubble.modelData.item)
			}
		}
	}
}
