import QtQuick

Item {
	id: root

	property var levels: []
	property bool flip: false
	property color ink: "#ffffff"

	readonly property real pitch: root.height / 4
	readonly property real dot: root.pitch * 0.6

	Repeater {
		model: root.levels

		delegate: Item {
			id: column

			required property int index
			required property int modelData

			x: column.index * root.pitch
			width: root.pitch
			height: root.height

			Repeater {
				model: column.modelData

				delegate: Rectangle {
					required property int index

					x: (root.pitch - root.dot) / 2
					y: (root.flip ? 3 - index : index) * root.pitch + (root.pitch - root.dot) / 2
					width: root.dot
					height: root.dot
					radius: root.dot / 2
					antialiasing: true
					color: root.ink
				}
			}
		}
	}
}
