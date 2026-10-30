import QtQuick
import qs
import qs.services

Item {
	id: root

	property real strength: 1

	readonly property int step: 28
	readonly property int count: 5
	readonly property int length: 22

	Repeater {
		model: root.count

		delegate: Item {
			id: pipe

			required property int index

			property var path: []
			property int grown: 0

			readonly property color tint: Qt.hsla(0.03 + index * 0.19, 0.78, 0.56)

			width: root.width
			height: root.height

			function build() {
				const cols = Math.max(4, Math.floor(root.width / root.step));
				const rows = Math.max(4, Math.floor(root.height / root.step));

				let x = Math.floor(Math.random() * cols);
				let y = Math.floor(Math.random() * rows);
				let dx = Math.random() < 0.5 ? 1 : -1;
				let dy = 0;
				const marks = [];

				for (let i = 0; i < root.length; i++) {
					marks.push({ x: x, y: y });

					if (i > 2 && Math.random() < 0.3) {
						const swap = dx;

						dx = dy;
						dy = swap;
					}

					x = Math.min(cols - 1, Math.max(0, x + dx));
					y = Math.min(rows - 1, Math.max(0, y + dy));

					if (x <= 0 || x >= cols - 1) dx = -dx;
					if (y <= 0 || y >= rows - 1) dy = -dy;
				}

				pipe.path = marks;
			}

			SequentialAnimation {
				running: true
				loops: Animation.Infinite

				ScriptAction { script: pipe.build() }
				PauseAnimation { duration: 800 + pipe.index * 400 }
				NumberAnimation { target: pipe; property: "grown"; from: 0; to: root.length; duration: 6500 }
				PauseAnimation { duration: 1800 }
			}

			Repeater {
				model: pipe.path

				delegate: Rectangle {
					required property int index
					required property var modelData

					x: modelData.x * root.step
					y: modelData.y * root.step
					width: root.step
					height: root.step
					radius: root.step * 0.32
					color: pipe.tint
					opacity: index <= pipe.grown ? root.strength : 0
				}
			}
		}
	}
}
