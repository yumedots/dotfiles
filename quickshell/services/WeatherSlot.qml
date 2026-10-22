import QtQuick
import Quickshell
import qs

Item {
	id: root

	property string place: ""
	property var known: ({})
	property bool primary: false
	property string temp: ""
	property string feels: ""
	property string wind: ""
	property string humidity: ""
	property var days: []
	property int modelCode: -1
	property int stationCode: -1
	property bool failed: false

	readonly property int code: root.stationCode >= 0 ? root.stationCode : root.modelCode
	readonly property var info: Forecast.weatherCodeInfo(root.code, Config.weatherCodes, Config.weatherIcon)
	readonly property string icon: root.place === "" ? "" : (root.temp !== "" ? root.info.glyph : Config.weatherLoadingIcon)
	readonly property string description: root.info.name

	onPlaceChanged: {
		root.reset();
		root.refresh();
	}

	Component.onCompleted: root.refresh()

	function reset() {
		root.modelCode = -1;
		root.stationCode = -1;
		root.temp = "";
		root.feels = "";
		root.wind = "";
		root.humidity = "";
		root.days = [];
		root.failed = false;
	}

	function refresh() {
		if (root.place === "")
			return;

		const spot = Forecast.coordsFor(root.known, root.place);

		if (spot.lat !== 0 && spot.lon !== 0) {
			fetch.command = Shell.curl(Forecast.weatherForecastUrl(spot.lat, spot.lon, Config.weatherTempUnit, Config.weatherWindUnit, Config.weatherDays));
			fetch.running = true;
			return;
		}

		geo.command = Shell.curl(Forecast.weatherGeoUrl(root.place));
		geo.running = true;
	}

	function fail() {
		root.failed = true;
		retry.interval = Math.min(retry.interval * 2, Config.weatherRefreshMs);
		retry.restart();
	}

	Request {
		id: geo

		onDone: function (text) {
			const found = Forecast.parseWeatherGeo(text);

			if (!found) {
				root.reset();
				root.fail();
				return;
			}

			fetch.command = Shell.curl(Forecast.weatherForecastUrl(found.lat, found.lon, Config.weatherTempUnit, Config.weatherWindUnit, Config.weatherDays));
			fetch.running = true;
			Weather.rememberCoords(root.place, found.lat, found.lon);
		}
	}

	Request {
		id: fetch

		onDone: function (text) {
			const parsed = Forecast.parseWeatherCurrent(text, Config.weatherTempUnit);

			if (parsed === null) {
				root.fail();
				return;
			}

			root.modelCode = Forecast.weatherCodeFor(parsed.code, parsed.precip);
			root.temp = parsed.temp;
			root.feels = parsed.feels;
			root.wind = parsed.wind;
			root.humidity = parsed.humidity;
			root.days = Forecast.parseWeatherDaily(text, Config.weatherTempUnit);
			root.failed = false;
			retry.stop();
			retry.interval = Config.weatherRetryMs;
		}
	}

	Timer {
		interval: Config.weatherRefreshMs
		running: root.place !== ""
		repeat: true
		onTriggered: root.refresh()
	}

	Timer {
		id: retry

		interval: Config.weatherRetryMs
		onTriggered: root.refresh()
	}
}
