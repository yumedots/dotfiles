import QtQuick
import qs

Item {
	id: root

	property var values: []
	property int columns: 16
	property real cellSize: 12
	property real gap: 4
	property var colorFor: null

	readonly property int step: root.cellSize + root.gap
	readonly property int rows: Math.max(1, Math.ceil(root.values.length / Math.max(1, root.columns)))

	implicitWidth: root.values.length === 0 ? 0 : root.columns * root.step - root.gap
	implicitHeight: root.values.length === 0 ? 0 : root.rows * root.step - root.gap

	Repeater {
		model: root.values

		delegate: Rectangle {
			required property var modelData
			required property int index

			x: (index % root.columns) * root.step
			y: Math.floor(index / root.columns) * root.step
			width: root.cellSize
			height: root.cellSize
			visible: modelData !== null
			radius: 0
			color: root.colorFor ? root.colorFor(modelData, index) : Config.cpuIdle
		}
	}
}
