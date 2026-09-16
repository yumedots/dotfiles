import QtQuick
import qs.ui
import qs.services
import qs
import "../../tooltips"

BarStat {
	id: root

	property var bar: null

	icon: Config.iconGithub
	value: Github.login !== "" ? String(Github.todayCount) : ""
	pct: Math.min(4, Github.todayLevel) * 100 / 4
	barColor: Github.login === "" ? Config.dim : Config.contribBase
	textColor: Github.login === "" ? Config.dim : Config.contribBase

	function openPopup() {
		popup.open();
	}

	function closePopup() {
		popup.hideNow();
	}

	function isPopupOpen() {
		return popup.shown;
	}

	Tooltip {
		id: popup

		anchorWindow: root.bar
		anchorItem: root
		wantsKeyboard: true

		GithubGrid {
			onCloseRequested: popup.close()
			onRefreshRequested: Github.refresh(true)
		}
	}
}
