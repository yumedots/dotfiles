import QtQuick
import qs.ui
import qs
import qs.services
import "../../tooltips"

BarStat {
	id: root

	inkId: "media"

	icon: Config.iconApp
	readonly property bool wanted: Yudae.mediaState.wanted === true
	visible: root.wanted
	popupPreload: true

	onWantedChanged: if (!root.visible) root.closePopup()

	popupContent: Component {
		MediaControl {
			onCloseRequested: root.closePopup()
		}
	}
}
