pragma Singleton

import QtQuick
import Quickshell
import qs

// The GitHub contribution grid, read from yudaemond. The daemon finds the
// login, fetches the page, parses the days and lays out the grid.
QtObject {
	id: root

	readonly property var source: Yudae.github

	readonly property string login: root.source.login || ""
	readonly property int total: root.source.total || 0
	readonly property real fetched: root.source.fetched || 0
	readonly property string status: root.source.status || ""
	readonly property bool loading: false
	readonly property var days: root.source.days || []
	readonly property var levelInk: root.source ? (root.source.levelInk || []) : []

	readonly property var grid: root.source.grid || []
	readonly property int todayCount: root.source.todayCount || 0
	readonly property int todayLevel: root.source.todayLevel || 0

	function refresh(force) {
		if (force)
			Yudae.send({ refresh: true });
	}
}
