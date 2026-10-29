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
	barColor: Config.mono ? Config.weatherBaseMono : Config.weatherBase
	icon: Weather.current.code >= 0 ? Weather.current.icon : Config.weatherLoadingIcon

	popupContent: Component {
		WeatherCard {
			onCloseRequested: root.closePopup()
		}
	}
}
