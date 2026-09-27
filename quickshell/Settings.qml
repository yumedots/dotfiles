pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

QtObject {
	id: root

	property int fontSize: Config.fontSize
	property int iconSize: Config.iconSize
	property string record: ""

	readonly property string path: Quickshell.shellDir + "/" + Config.displayFile
	readonly property var state: Display.stateFromText(root.record)

	function apply(text) {
		const state = Display.stateFromText(text);

		root.record = text;

		if (state.fontSize > 0)
			root.fontSize = state.fontSize;
		if (state.iconSize > 0)
			root.iconSize = state.iconSize;
	}

	function reload() {
		file.reload();
	}

	function save(state) {
		root.record = Display.renderLua(state);

		if (state.fontSize > 0) {
			root.fontSize = state.fontSize;
			root.iconSize = state.iconSize;
		}

		Quickshell.execDetached(Shell.writeCommand(root.path, root.record));
	}

	property FileView file: FileView {
		path: root.path
		blockLoading: true
		watchChanges: true

		onFileChanged: file.reload()
		onLoaded: root.apply(file.text())
	}
}
