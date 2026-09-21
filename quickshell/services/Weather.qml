pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Item {
	id: root

	property string description: ""
	property string location: ""
	property string place: ""
	property string temp: ""
	property string feels: ""
	property string wind: ""
	property string humidity: ""
	property real lat: 0
	property real lon: 0
	property int code: -1
	property var stations: []
	property bool placeFailed: false
	property real fetched: 0
	property bool loading: false
	property string status: ""
	property string tracked: ""

	readonly property string dir: Quickshell.shellDir + "/cache/weather"
	readonly property string placeFile: root.dir + "/place"
	readonly property string wanted: root.tracked !== "" ? root.tracked : Config.weatherLocation
	readonly property string cacheFile: root.dir + "/current.json"
	readonly property var codeInfo: Forecast.weatherCodeInfo(root.code, Config.weatherCodes, Config.weatherIcon)
	readonly property string icon: root.codeInfo.glyph

	function adopt(cached) {
		root.description = cached.description || "";
		root.location = cached.location || "";
		root.place = cached.place || "";
		root.temp = cached.temp || "";
		root.feels = cached.feels || "";
		root.wind = cached.wind || "";
		root.humidity = cached.humidity || "";
		root.lat = cached.lat || 0;
		root.lon = cached.lon || 0;
		root.code = typeof cached.code === "number" ? cached.code : -1;
		root.stations = cached.stations || [];
		root.placeFailed = cached.placeFailed === true;
		root.fetched = cached.fetched || 0;
	}

	function save() {
		cache.save({
			fetched: root.fetched,
			description: root.description,
			location: root.location,
			place: root.place,
			temp: root.temp,
			feels: root.feels,
			wind: root.wind,
			humidity: root.humidity,
			lat: root.lat,
			lon: root.lon,
			code: root.code,
			stations: root.stations,
			placeFailed: root.placeFailed
		});
	}

	function refresh(force) {
		if (root.loading)
			return;

		root.loading = true;
		cache.read(force);
	}

	function locate() {
		const fixed = Forecast.parseCoords(Config.weatherCoords);

		if (fixed) {
			root.lat = fixed.lat;
			root.lon = fixed.lon;
			root.place = root.wanted;
			root.location = root.wanted;
			fetch.running = true;
			return;
		}

		if (root.lat !== 0 && root.lon !== 0) {
			root.place = root.wanted;

			if (root.location === "")
				root.location = root.wanted;

			fetch.running = true;
			return;
		}

		geocode.running = true;
	}

	function observe() {
		if (Config.weatherStationCount <= 0 || root.placeFailed)
			return;

		if (root.stations.length > 0) {
			observe.running = true;
			return;
		}

		points.running = true;
	}

	Component.onCompleted: placeRead.running = true

	Timer {
		interval: Config.weatherRefreshMs
		running: true
		repeat: true

		onTriggered: root.refresh(true)
	}

	Request {
		id: placeRead

		command: Shell.readCommand(root.placeFile)

		onDone: function (text) {
			root.tracked = text.trim();
			root.refresh(false);
		}
	}

	CachedFile {
		id: cache

		path: root.cacheFile
		maxAge: Config.weatherCacheMs

		onLoaded: function (data, stale) {
			root.adopt(data);

			if (root.place !== root.wanted) {
				root.stations = [];
				root.placeFailed = false;
			}

			if (!stale && root.temp !== "" && root.place === root.wanted) {
				root.loading = false;
				root.status = "";
				return;
			}

			root.locate();
		}
	}

	Request {
		id: geocode

		command: Shell.curl(Forecast.weatherGeoUrl(root.wanted))

		onDone: function (text) {
			const found = Forecast.parseWeatherGeo(text, Forecast.weatherRegion(root.wanted));

			if (!found) {
				root.loading = false;
				root.status = root.temp !== "" ? "" : "no location";
				return;
			}

			root.lat = found.lat;
			root.lon = found.lon;
			root.place = root.wanted;
			root.location = found.place;
			fetch.running = true;
		}
	}

	Request {
		id: fetch

		command: Shell.curl(Forecast.weatherForecastUrl(root.lat, root.lon))

		onDone: function (text) {
			const parsed = Forecast.parseWeatherCurrent(text);

			root.loading = false;

			if (parsed === null) {
				root.status = root.temp !== "" ? "" : "no response";
				return;
			}

			root.code = Forecast.weatherCodeFor(parsed.code, parsed.precip);
			root.description = root.codeInfo.name;
			root.temp = parsed.temp;
			root.feels = parsed.feels;
			root.wind = parsed.wind;
			root.humidity = parsed.humidity;
			root.fetched = Date.now();
			root.status = "";
			root.save();
			root.observe();
		}
	}

	Request {
		id: points

		command: ["sh", "-c", Forecast.weatherRequest(Shell.shellQuote(Forecast.weatherPointsUrl(root.lat, root.lon)))]

		onDone: function (text) {
			const list = Forecast.parseWeatherPoints(text);

			if (list === null) {
				if (text !== "")
					root.placeFailed = true;

				return;
			}

			stations.command = ["sh", "-c", Forecast.weatherRequest(Shell.shellQuote(list))];
			stations.running = true;
		}
	}

	Request {
		id: stations

		onDone: function (text) {
			const ids = Forecast.parseWeatherStationIds(text, root.lat, root.lon, Config.weatherStationCount);

			if (ids.length === 0) {
				root.placeFailed = true;
				return;
			}

			root.stations = ids;
			observe.running = true;
		}
	}

	Request {
		id: observe

		command: ["sh", "-c", Forecast.weatherRequest(root.stations.map(function (id) { return Shell.shellQuote(Forecast.weatherObservationUrl(id)); }).join(" "))]

		onDone: function (text) {
			const rows = Forecast.parseWeatherObservations(text);
			const near = Forecast.weatherObservationCode(rows);

			if (near < 0)
				return;

			root.code = near;
			root.description = root.codeInfo.name;
			root.save();
		}
	}
}
