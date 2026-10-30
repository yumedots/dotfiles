import QtQuick
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
	property var onPick

	property int held: -1
	property bool lens: false
	property bool grabbed: false

	readonly property int count: root.model.length
	readonly property real cellSize: root.count > 0 ? ((root.vertical ? root.height : root.width) - (root.count - 1) * root.gap) / root.count : 0
	readonly property int hovered: bar.containsMouse && root.count > 0 ? root.indexAt(bar.mouseX, bar.mouseY) : -1
	readonly property string hoverLabel: root.entryLabel(root.hovered)
	readonly property bool solid: root.level >= 0
	readonly property real filled: Calc.clamp(root.level, 0, 1)
	readonly property real thickness: root.vertical ? root.width : root.height
	readonly property real lensSize: root.thickness + Config.stepBarLensPad * 2
	readonly property real lensAt: root.held < 0 ? 0 : Math.min(root.held * (root.cellSize + root.gap) + root.cellSize, (root.vertical ? root.height : root.width) - root.lensSize / 2)

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

	function mark(x, y) {
		if (root.count <= 0)
			return;

		const index = x !== undefined ? root.indexAt(x, y) : root.cursor >= 0 ? root.cursor : root.selected;

		if (index < 0)
			return;

		root.held = index;
		root.lens = true;
		lensIdle.restart();
	}

	onCursorChanged: root.mark()
	onSelectedChanged: root.mark()

	Timer {
		id: lensIdle

		interval: Config.stepBarLensHold
		onTriggered: if (!root.grabbed) root.lens = false
	}

	onGrabbedChanged: if (!root.grabbed && root.lens) lensIdle.restart()

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

	MouseArea {
		id: bar

		anchors.fill: parent
		acceptedButtons: Qt.NoButton
		hoverEnabled: true

		onPositionChanged: (mouse) => root.mark(mouse.x, mouse.y)
		onContainsMouseChanged: {
			if (bar.containsMouse)
				root.mark(bar.mouseX, bar.mouseY);
			else
				root.lens = false;
		}
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

					onPressedChanged: root.grabbed = pressed
					onClicked: root.pick(segment.modelData);
				}
			}
		}
	}

	Item {
		id: lensMark

		width: root.vertical ? root.width : root.lensSize + 4
		height: root.vertical ? root.lensSize + 4 : root.height
		opacity: root.lens ? 1 : 0
		scale: root.lens ? 1 : 0.7
		x: root.vertical ? 0 : root.lensAt - width / 2
		y: root.vertical ? root.lensAt - height / 2 : 0

		Rectangle {
			anchors.fill: parent
			color: Config.surfaceTranslucent
		}

		Rectangle {
			anchors.centerIn: parent
			width: root.lensSize
			height: width
			radius: width / 2
			color: root.ink
			antialiasing: true
		}

		Behavior on x {
			enabled: root.lens
			NumberAnimation { duration: Config.stepBarLensGlide; easing.type: Easing.OutCubic }
		}

		Behavior on y {
			enabled: root.lens
			NumberAnimation { duration: Config.stepBarLensGlide; easing.type: Easing.OutCubic }
		}

		Behavior on opacity {
			NumberAnimation { duration: root.lens ? Config.stepBarLensGlide : Config.stepBarLensFade; easing.type: Easing.OutCubic }
		}

		Behavior on scale {
			NumberAnimation { duration: root.lens ? Config.stepBarLensGlide : Config.stepBarLensFade; easing.type: Easing.OutCubic }
		}
	}
}
