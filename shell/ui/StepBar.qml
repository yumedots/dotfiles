import QtQuick
import QtQuick.Shapes
import qs
import qs.services

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
	property var formatter: null
	property real hitPad: 0
	property var onPick
	property bool follow: true
	property bool circular: false
	property real ringWidth: Config.stepBarHeight

	readonly property int count: root.model.length
	readonly property real ringSize: Math.min(root.width, root.height)
	readonly property real ringRadius: Math.max(0, root.ringSize / 2 - root.ringWidth / 2)
	readonly property real cellSize: root.count > 0 ? ((root.vertical ? root.height : root.width) - (root.count - 1) * root.gap) / root.count : 0
	readonly property int hovered: root.follow && bar.containsMouse && root.count > 0 ? root.indexAt(bar.mouseX, bar.mouseY) : -1
	readonly property int hoverRank: root.hovered < 0 ? -1 : root.vertical ? root.count - 1 - root.hovered : root.hovered
	readonly property int shown: root.hoverRank >= 0 ? root.hoverRank : root.selected
	readonly property string hoverLabel: root.entryLabel(root.hovered)
	readonly property bool solid: root.level >= 0
	readonly property real filled: Calc.clamp(root.level, 0, 1)
	readonly property real thickness: root.vertical ? root.width : root.height
	readonly property real lensSize: root.thickness + Config.stepBarLensPad * 2
	readonly property real lensAt: {
		const slot = root.vertical ? root.count - 1 - root.shown : root.shown;
		const edge = slot * (root.cellSize + root.gap) + (root.vertical ? 0 : root.cellSize);
		return Calc.clamp(edge, root.lensSize / 2, (root.vertical ? root.height : root.width) - root.lensSize / 2);
	}

	implicitHeight: Config.stepBarHeight

	function indexAt(x, y) {
		const at = root.vertical ? y : x;
		const slot = Math.floor(at / (root.cellSize + root.gap));

		return Calc.clamp(slot, 0, root.count - 1);
	}

	function valueOf(entry) {
		return entry !== null && entry !== undefined && entry.value !== undefined ? entry.value : entry;
	}

	function entryLabel(index) {
		if (index < 0 || index >= root.count)
			return "";

		const entry = root.model[index];
		const label = entry !== null && entry !== undefined && entry.label !== undefined ? String(entry.label) : String(entry);

		return root.formatter !== null ? root.formatter(label) : label;
	}

	function pick(entry) {
		if (root.onPick)
			root.onPick(root.valueOf(entry));
	}

	Rectangle {
		visible: root.solid && !root.circular
		anchors.fill: parent
		color: root.track
	}

	Rectangle {
		visible: root.solid && !root.circular
		anchors.bottom: parent.bottom
		anchors.left: parent.left
		width: root.vertical ? root.width : root.width * root.filled
		height: root.vertical ? root.height * root.filled : root.height
		color: root.ink
	}

	Rectangle {
		visible: root.solid && root.circular
		anchors.centerIn: parent
		width: root.ringSize
		height: root.ringSize
		radius: root.ringSize / 2
		color: "transparent"
		border.width: root.ringWidth
		border.color: root.track
		antialiasing: true
	}

	Shape {
		visible: root.solid && root.circular && root.filled > 0
		anchors.centerIn: parent
		width: root.ringSize
		height: root.ringSize
		preferredRendererType: Shape.CurveRenderer
		asynchronous: false
		antialiasing: true

		ShapePath {
			fillColor: "transparent"
			strokeColor: root.ink
			strokeWidth: root.ringWidth
			capStyle: ShapePath.RoundCap

			PathAngleArc {
				centerX: root.ringSize / 2
				centerY: root.ringSize / 2
				radiusX: root.ringRadius
				radiusY: root.ringRadius
				startAngle: -90
				sweepAngle: root.filled * 359.99
				moveToStart: true
			}
		}
	}

	MouseArea {
		id: bar

		anchors.fill: parent
		anchors.topMargin: root.vertical ? 0 : -root.hitPad
		anchors.bottomMargin: root.vertical ? 0 : -root.hitPad
		anchors.leftMargin: root.vertical ? -root.hitPad : 0
		anchors.rightMargin: root.vertical ? -root.hitPad : 0
		acceptedButtons: Qt.NoButton
		hoverEnabled: true
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

				Behavior on color {
					ColorAnimation {
						duration: 120
						easing.type: Easing.OutCubic
					}
				}

				Highlight {
					active: root.cursor === segment.index
				}

				MouseArea {
					anchors.fill: parent

					onClicked: root.pick(segment.modelData)
				}
			}
		}
	}

	Rectangle {
		id: lensMark

		readonly property real size: root.lensSize + 4

		width: size
		height: size
		radius: size / 2
		color: root.ink
		border.width: 2
		border.color: Config.surface
		antialiasing: true
		visible: !root.solid && root.shown >= 0
		x: root.vertical ? (root.width - size) / 2 : root.lensAt - size / 2
		y: root.vertical ? root.lensAt - size / 2 : (root.height - size) / 2

		Behavior on x {
			NumberAnimation {
				duration: 120
				easing.type: Easing.OutCubic
			}
		}

		Behavior on y {
			NumberAnimation {
				duration: 120
				easing.type: Easing.OutCubic
			}
		}
	}
}
