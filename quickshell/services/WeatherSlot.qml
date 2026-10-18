import QtQuick
import Quickshell
import qs

Item {
	id: root

	property string place: ""
	property var known: ({})
	property bool primary: false
	property int code: -1
	property string temp: ""

	readonly property var info: Forecast.weatherCodeInfo(root.code, Config.weatherCodes, Config.weatherIcon)
	readonly property string icon: root.temp !== "" ? root.info.glyph : Config.weatherLoadingIcon
	readonly property string description: root.info.name

	onPlaceChanged: root.refresh()
	Component.onCompleted: root.refresh()
	onCodeChanged: if (root.primary) Weather.primaryCode = root.code

	function refresh() {
		if (root.place === "")
			return;

		const spot = Forecast.coordsFor(root.known, root.place);

		if (spot.lat !== 0 && spot.lon !== 0) {
			fetch.command = Shell.curl(Forecast.weatherForecastUrl(spot.lat, spot.lon));
			fetch.running = true;
			return;
		}

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
			Weather.rememberCoords(root.place, found.lat, found.lon);
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
