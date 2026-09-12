import QtQuick
import Quickshell.Hyprland
import "theme.js" as Theme

Row {
	id: root
	spacing: Theme.workspaceSpacing

	readonly property var persistentIds: [1, 2, 3, 4]

	readonly property var ids: {
		const ids = new Set(root.persistentIds);
		const workspaces = Hyprland.workspaces.values;
		for (let i = 0; i < workspaces.length; i++) {
			if (workspaces[i].id > 0)
				ids.add(workspaces[i].id);
		}
		return Array.from(ids).sort(function (a, b) {
			return a - b;
		});
	}

	readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

	Repeater {
		model: root.ids

		delegate: BarText {
			required property var modelData

			text: "" + modelData
			padding: Theme.workspacePadding
			color: root.focusedId === modelData ? Theme.workspaceActive : Theme.workspaceInactive

			MouseArea {
				anchors.fill: parent
				onClicked: Hyprland.dispatch("workspace " + modelData)
			}
		}
	}
}
