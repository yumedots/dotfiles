import QtQuick
import qs.ui
import qs
import qs.services

BarStat {
	id: root

	inkId: "weather"

	mode: "icon"
	showBar: false
	iconSize: Settings.iconSize + 4
	iconLift: -2.5 + (root.glyphInkHeight - Settings.iconSize) / 5
	readonly property real baselineLift: Math.ceil(Config.barThickness)
	barColor: Config.mono ? Config.weatherBaseMono : Config.weatherBase
	icon: Weather.current.code >= 0 ? Weather.current.icon : Config.weatherLoadingIcon

	popupContent: Component {
		WeatherCard {
			onCloseRequested: root.closePopup()
		}
	}
}
