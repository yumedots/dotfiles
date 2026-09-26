import QtQuick
import Quickshell.Services.Mpris
import qs.ui
import qs
import "../../tooltips"

BarStat {
	id: root

	readonly property var player: Media.pickPlayer(Mpris.players.values ? Mpris.players.values : [])

	icon: Config.iconApp
	readonly property bool wanted: Media.hasContent(root.player)
	visible: root.wanted
	popupWanted: root.wanted

	onPlayerChanged: if (!root.visible) root.closePopup()

	popupContent: MediaControl {
		player: root.player

		onCloseRequested: root.closePopup()
	}
}
