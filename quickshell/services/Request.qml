import QtQuick
import Quickshell.Io

Item {
	id: root

	property alias command: runner.command
	property alias running: runner.running

	signal done(string text)

	Process {
		id: runner

		stdout: StdioCollector {
			onStreamFinished: root.done(text)
		}
	}
}
