import QtQuick
import qs

Item {
	id: root

	property var model: []
	property int selected: -1
	property real level: -1
	property int cursor: -1
	property bool vertical: false
	property color ink: Config.foreground
	property color track: Config.dim
	property real gap: Config.stepBarGap
	property int hovered: -1
	property var onPick

	readonly property int count: root.model.length
	readonly property real cellSize: root.count > 0 ? ((root.vertical ? root.height : root.width) - (root.count - 1) * root.gap) / root.count : 0
	readonly property string hoverLabel: root.entryLabel(root.hovered)
	readonly property bool solid: root.level >= 0
	readonly property real filled: Util.clamp(root.level, 0, 1)

	implicitHeight: Config.stepBarHeight

	function valueOf(entry) {
		return entry !== null && entry !== undefined && entry.value !== undefined ? entry.value : entry;
	}

	function entryLabel(index) {
		if (index < 0 || index >= root.count)
			return "";

		const entry = root.model[index];

		return entry !== null && entry !== undefined && entry.label !== undefined ? String(entry.label) : String(entry);
	}

	function pick(entry) {
		if (root.onPick)
			root.onPick(root.valueOf(entry));
	}

	Rectangle {
		visible: root.solid
		anchors.fill: parent
		color: root.track
	}

	Rectangle {
		visible: root.solid
		anchors.bottom: parent.bottom
		anchors.left: parent.left
		width: root.vertical ? root.width : root.width * root.filled
		height: root.vertical ? root.height * root.filled : root.height
		color: root.ink
	}

	Grid {
		visible: !root.solid
		columns: Math.max(1, root.vertical ? 1 : root.count)
		rowSpacing: root.gap
		columnSpacing: root.gap

		Repeater {
			model: root.model

			delegate: Rectangle {
				id: segment

				required property var modelData
				required property int index

				readonly property int rank: root.vertical ? root.count - 1 - segment.index : segment.index

				width: root.vertical ? root.width : root.cellSize
				height: root.vertical ? root.cellSize : root.height
				color: segment.rank <= root.selected ? root.ink : root.track

				Highlight {
					active: root.cursor === segment.index
				}

				MouseArea {
					anchors.fill: parent
					hoverEnabled: true

					onEntered: root.hovered = segment.index
					onExited: root.hovered = -1
					onClicked: root.pick(segment.modelData);
				}
			}
		}
	}
}
