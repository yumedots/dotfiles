import QtQuick
import Quickshell
import qs

Item {
	id: root

	property string place: ""
	property int code: -1
	property string temp: ""

	readonly property var info: Forecast.weatherCodeInfo(root.code, Config.weatherCodes, Config.weatherIcon)
	readonly property string icon: root.temp !== "" ? root.info.glyph : Config.weatherLoadingIcon
	readonly property string description: root.info.name

	onPlaceChanged: root.refresh()
	Component.onCompleted: root.refresh()

	function refresh() {
		if (root.place === "")
			return;

		geo.command = Shell.curl(Forecast.weatherGeoUrl(root.place));
		geo.running = true;
	}

	Request {
		id: geo

		onDone: function (text) {
			const found = Forecast.parseWeatherGeo(text);

			if (!found) {
				root.code = -1;
				root.temp = "";
				return;
			}

			fetch.command = Shell.curl(Forecast.weatherForecastUrl(found.lat, found.lon));
			fetch.running = true;
		}
	}

	Request {
		id: fetch

		onDone: function (text) {
			const parsed = Forecast.parseWeatherCurrent(text);

			if (parsed === null)
				return;

			root.code = Forecast.weatherCodeFor(parsed.code, parsed.precip);
			root.temp = parsed.temp;
		}
	}

	Timer {
		interval: Config.weatherRefreshMs
		running: root.place !== ""
		repeat: true
		onTriggered: root.refresh()
	}
}
