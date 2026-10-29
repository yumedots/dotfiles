pragma Singleton

import QtQuick
import Quickshell
import qs
import qs.ui

// The weather, read from yudaemond. The daemon watches the places, geocodes
// them, fetches open-meteo and the nearest station; this only names the code
// and lays the numbers out.
Item {
	id: root

	readonly property var source: Yudae.weatherState
	readonly property var places: root.source.places || []
	readonly property int index: root.source.index || 0
	readonly property var rawSlots: root.source.slots || []
	readonly property var focused: root.rawSlots[root.index] || ({})

	readonly property int code: root.focused.code === undefined ? -1 : root.focused.code
	readonly property string icon: root.focused.glyph || Config.weatherIcon

	readonly property var days: root.focused.days || []
	readonly property var suggestions: root.source.suggestions || []
	readonly property var matches: root.source.rows || []
	readonly property string ghost: root.source.ghost || ""
	readonly property string status: root.source.status || ""
	readonly property real fetched: root.source.fetched || 0
	readonly property bool loading: (root.focused.tempValue || "") === ""

	readonly property var current: ({
		tempValue: root.focused.tempValue || "",
		tempUnit: root.focused.tempUnit || "",
		feels: root.focused.feels || "",
		wind: root.focused.wind || "",
		humidity: root.focused.humidity || "",
		code: root.code,
		icon: root.icon,
		place: String(root.places[root.index] || "").split(",")[0].trim(),
		loading: root.loading
	})

	function shift(step) {
		Yudae.weather({ shift: step < 0 ? -1 : 1 });
	}

	function choose(label, lat, lon) {
		Yudae.weather({ choose: { label: label, lat: lat, lon: lon } });
	}

	function add(label, lat, lon) {
		Yudae.weather({ add: { label: label, lat: lat, lon: lon } });
	}

	function search(query) {
		Yudae.weather({ search: String(query || "") });
	}

	function query(value) {
		Yudae.weather({ query: String(value || "") });
	}

	function refresh(force) {
		if (force)
			Yudae.send({ refresh: true });
	}
}
