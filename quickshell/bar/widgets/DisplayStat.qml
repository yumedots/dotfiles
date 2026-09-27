import QtQuick
import qs.ui
import qs
import qs.services
import "../../tooltips"

BarStat {
	id: root

	property string raw: ""

	readonly property var listed: Display.monitorsFromText(root.raw)

	mode: "icon"
	icon: Config.iconDisplay
	barColor: Util.pick(Config.mono, Config.displayBase, Config.displayBaseMono)
	textColor: root.barColor

	function refresh() {
		if (!poll.running)
			poll.running = true;
	}

	onPopupVisibleChanged: if (!root.popupVisible) delayed.restart()

	Component.onCompleted: root.refresh()

	Request {
		id: poll

		command: ["hyprctl", "monitors", "-j"]

		onDone: function (text) { root.raw = text; }
	}

	Timer {
		id: delayed

		interval: 800
		repeat: false
		onTriggered: root.refresh()
	}

	popupContent: DisplayPanel {
		shown: root.popupVisible
		raw: root.raw
		monitors: root.listed
		onCloseRequested: root.closePopup()
		onChanged: delayed.restart()
	}
}
