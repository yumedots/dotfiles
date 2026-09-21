import QtQuick
import qs.ui
import qs.services
import qs
import "../../tooltips"

BarStat {
	id: root

	icon: Config.iconGithub
	value: Github.login !== "" ? String(Github.todayCount) : ""
	pct: Math.min(4, Github.todayLevel) * 100 / 4
	barColor: Github.login === "" ? Config.dim : Config.contribBase
	textColor: Config.contribBase
	dim: Github.login === ""

	popupContent: GithubGrid {
		onCloseRequested: root.closePopup()
		onRefreshRequested: Github.refresh(true)
	}
}
