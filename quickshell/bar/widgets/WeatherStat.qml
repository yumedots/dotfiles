import QtQuick
import qs.ui
import qs
import qs.services
import "../../tooltips"

BarStat {
	id: root

	inkId: "weather"

	mode: "icon"
	showBar: false
	iconSize: Settings.iconSize + 4
	iconLift: -1
	barColor: Util.pick(Config.mono, Config.weatherBase, Config.weatherBaseMono)
	icon: Weather.primaryCode >= 0 ? Weather.primaryIcon : Config.weatherLoadingIcon

	popupContent: Component {
		WeatherCard {
			onCloseRequested: root.closePopup()
		}
	}
}
