import QtQuick
import Quickshell.Hyprland
import "config.js" as Config

Row {
	id: root
	spacing: Config.workspaceSpacing

	readonly property int pool: 10
	readonly property var persistentIds: [1, 2, 3, 4]
	property var ids: []
	property int focusedId: -1

	readonly property string liveState: {
		const workspaces = Hyprland.workspaces.values;
		return workspaces.map(function (w) { return w.id; }).join(",") + "|" + (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1);
	}

	function settle() {
		const ids = root.persistentIds.concat(Hyprland.workspaces.values.filter(function (w) { return w.id > 0; }).map(function (w) { return w.id; }));
		root.ids = Array.from(new Set(ids));
		root.focusedId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
	}

	Component.onCompleted: root.settle()
	onLiveStateChanged: debounce.restart()

	Timer {
		id: debounce

		interval: 7

		onTriggered: root.settle()
	}

	Repeater {
		model: root.pool

		delegate: BarText {
			id: ws

			required property int index

			readonly property int workspaceId: index + 1

			visible: root.ids.indexOf(ws.workspaceId) >= 0
			text: "" + ws.workspaceId
			padding: Config.workspacePadding
			color: root.focusedId === ws.workspaceId ? Config.workspaceActive : Config.workspaceInactive

			MouseArea {
				anchors.fill: parent
				onClicked: Hyprland.dispatch("workspace " + ws.workspaceId)
			}
		}
	}
}
