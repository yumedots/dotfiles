import QtQuick
import qs.ui
import qs
import qs.services
import "../../tooltips"

BarStat {
	id: root

	inkId: "display"

	readonly property var listed: Yudae.screenMonitors
	readonly property string raw: Yudae.screenRaw

	mode: "icon"
	icon: Config.iconDisplay
	barColor: Util.pick(Config.mono, Config.displayBase, Config.displayBaseMono)
	textColor: root.barColor

	popupContent: Component {
		DisplayPanel {
			shown: root.popupVisible
			raw: root.raw
			monitors: root.listed
			onCloseRequested: root.closePopup()
		}
	}
}
