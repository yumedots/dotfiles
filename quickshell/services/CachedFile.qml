import QtQuick
import Quickshell
import Quickshell.Io
import qs

Item {
	id: root

	property string path: ""
	property real maxAge: 0
	property bool force: false

	signal loaded(var data, bool stale)

	function read(want) {
		root.force = want === true;
		reader.running = true;
	}

	function save(payload) {
		Quickshell.execDetached(Shell.writeCommand(root.path, JSON.stringify(payload)));
	}

	function stale(data) {
		const fetched = data && data.fetched ? data.fetched : 0;

		return root.force || root.maxAge <= 0 || fetched <= 0 || (Date.now() - fetched) >= root.maxAge;
	}

	Process {
		id: reader

		command: Shell.readCommand(root.path)

		stdout: StdioCollector {
			onStreamFinished: {
				const data = Shell.readJson(text, null);
				const cached = data !== null && typeof data === "object" ? data : {};

				root.loaded(cached, root.stale(cached));
			}
		}
	}
}
