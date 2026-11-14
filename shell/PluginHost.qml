import QtQuick
import qs.services

Item {
	Repeater {
		model: Yudae.plugins.filter(function (plugin) {
			return plugin.kind === "shell" && plugin.state === "loaded" && plugin.entry !== "";
		})

		delegate: Loader {
			required property var modelData

			source: modelData.entry
		}
	}
}
