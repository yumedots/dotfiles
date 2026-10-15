import QtQuick
import Quickshell.Hyprland
import qs
import qs.services

Row {
	id: root
	spacing: Config.workspaceSpacing
	property var bar: null

	readonly property real baselineLift: Math.ceil(Config.barThickness)
	readonly property var persistentIds: [1, 2, 3, 4]
	readonly property int highest: root.ids.length > 0 ? root.ids[root.ids.length - 1] : 0
	readonly property int pool: Math.max(root.persistentIds.length, root.highest)
	property var ids: []
	property int focusedId: -1
	property color ink: BarInk.pick(root.bar, "workspaces", Config.foreground)

	Behavior on ink {
		enabled: BarInk.fading
		ColorAnimation {
			duration: BarInk.fadeMs
		}
	}

	readonly property string liveState: {
		const workspaces = Hyprland.workspaces.values;
		return workspaces.map(function (w) { return w.id; }).join(",") + "|" + (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1);
	}

	function focusWorkspace(id) {
		Hyprland.dispatch(Hyprland.usingLua
			? "hl.dsp.focus({ workspace = " + id + " })"
			: "workspace " + id);
	}

	function scroll(step) {
		const count = root.ids.length;

		if (!count)
			return;

		const focused = Hyprland.focusedWorkspace;
		const index = root.ids.indexOf(focused ? focused.id : root.focusedId);

		root.focusWorkspace(root.ids[(index + step + count) % count]);
	}

	function same(next) {
		return root.ids.length === next.length && next.every(function (id, index) { return root.ids[index] === id; });
	}

	function settle() {
		const ids = root.persistentIds.concat(Hyprland.workspaces.values.filter(function (w) { return w.id > 0; }).map(function (w) { return w.id; }));
		const next = Array.from(new Set(ids)).sort(function (left, right) { return left - right; });

		if (!root.same(next))
			root.ids = next;

		root.focusedId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
	}

	Component.onCompleted: root.settle()
	onLiveStateChanged: debounce.restart()

	Timer {
		id: debounce

		interval: 7

		onTriggered: root.settle()
	}

	TextMetrics {
		id: digitMetrics

		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		text: "8"
	}

	TextMetrics {
		id: sampleMetrics

		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		text: Config.valueSample
	}

	readonly property real slotWidth: digitMetrics.advanceWidth + 8
	readonly property real slotHeight: sampleMetrics.tightBoundingRect.height + 4

	Repeater {
		model: root.pool

		delegate: Item {
			id: ws

			required property int index

			readonly property int workspaceId: index + 1
			readonly property bool active: root.focusedId === ws.workspaceId

			visible: root.ids.indexOf(ws.workspaceId) >= 0

			readonly property bool boxed: ws.active && (BarInk.bare || (root.bar !== null && root.bar.layout.transparent === true))
			readonly property color labelColor: ws.boxed ? Qt.rgba(1 - root.ink.r, 1 - root.ink.g, 1 - root.ink.b, 1) : root.ink

			implicitWidth: ws.workspaceId >= 10 ? label.implicitWidth + 8 : root.slotWidth
			implicitHeight: sampleMetrics.tightBoundingRect.height

			Rectangle {
				id: selector

				width: ws.implicitWidth
				height: root.slotHeight
				radius: 4
				color: root.ink
				visible: ws.boxed

				x: 0
				y: (sampleMetrics.tightBoundingRect.height - root.slotHeight) / 2
			}

			Text {
				id: label

				anchors.centerIn: selector
				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: ws.labelColor
				text: "" + ws.workspaceId
			}

			MouseArea {
				anchors.fill: parent
				anchors.margins: -Config.barHitPadding

				onClicked: root.focusWorkspace(ws.workspaceId)
			}
		}
	}
}
