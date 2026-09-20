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
	readonly property var codeInfo: Helpers.weatherCodeInfo(root.code, Config.weatherCodes, Config.weatherIcon)
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
		const payload = JSON.stringify({
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

		Quickshell.execDetached(["sh", "-c", "mkdir -p " + Helpers.shellQuote(root.dir)
			+ " && printf '%s' " + Helpers.shellQuote(payload) + " > " + Helpers.shellQuote(root.cacheFile)]);
	}

	function refresh(force) {
		if (root.loading)
			return;

		root.loading = true;
		cacheRead.force = force === true;
		cacheRead.running = true;
	}

	function locate() {
		const fixed = Helpers.parseCoords(Config.weatherCoords);

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

	Process {
		id: placeRead

		command: ["sh", "-c", "cat " + Helpers.shellQuote(root.placeFile) + " 2>/dev/null"]

		stdout: StdioCollector {
			onStreamFinished: {
				root.tracked = text.trim();
				root.refresh(false);
			}
		}
	}

	Process {
		id: cacheRead

		property bool force: false

		command: ["sh", "-c", "cat " + Helpers.shellQuote(root.cacheFile) + " 2>/dev/null"]

		stdout: StdioCollector {
			onStreamFinished: {
				let cached = null;

				try {
					cached = JSON.parse(text);
				} catch (error) {
					cached = null;
				}

				root.adopt(cached || {});

				if (root.place !== root.wanted) {
					root.stations = [];
					root.placeFailed = false;
				}

				const recent = root.fetched > 0 && (Date.now() - root.fetched) < Config.weatherCacheMs && root.place === root.wanted;

				if (!cacheRead.force && root.temp !== "" && recent) {
					root.loading = false;
					root.status = "";
					return;
				}

				root.locate();
			}
		}
	}

	Process {
		id: geocode

		command: ["sh", "-c", "curl -s -m 15 " + Helpers.shellQuote(Helpers.weatherGeoUrl(root.wanted))]

		stdout: StdioCollector {
			onStreamFinished: {
				const found = Helpers.parseWeatherGeo(text, Helpers.weatherRegion(root.wanted));

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
	}

	Process {
		id: fetch

		command: ["sh", "-c", "curl -s -m 15 " + Helpers.shellQuote(Helpers.weatherForecastUrl(root.lat, root.lon))]

		stdout: StdioCollector {
			onStreamFinished: {
				const parsed = Helpers.parseWeatherCurrent(text);

				root.loading = false;

				if (parsed === null) {
					root.status = root.temp !== "" ? "" : "no response";
					return;
				}

				root.code = Helpers.weatherCodeFor(parsed.code, parsed.precip);
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
	}

	Process {
		id: points

		command: ["sh", "-c", Helpers.weatherRequest(Helpers.shellQuote(Helpers.weatherPointsUrl(root.lat, root.lon)))]

		stdout: StdioCollector {
			onStreamFinished: {
				const list = Helpers.parseWeatherPoints(text);

				if (list === null) {
					if (text !== "")
						root.placeFailed = true;

					return;
				}

				stations.command = ["sh", "-c", Helpers.weatherRequest(Helpers.shellQuote(list))];
				stations.running = true;
			}
		}
	}

	Process {
		id: stations

		stdout: StdioCollector {
			onStreamFinished: {
				const ids = Helpers.parseWeatherStationIds(text, root.lat, root.lon, Config.weatherStationCount);

				if (ids.length === 0) {
					root.placeFailed = true;
					return;
				}

				root.stations = ids;
				observe.running = true;
			}
		}
	}

	Process {
		id: observe

		command: ["sh", "-c", Helpers.weatherRequest(root.stations.map(function (id) { return Helpers.shellQuote(Helpers.weatherObservationUrl(id)); }).join(" "))]

		stdout: StdioCollector {
			onStreamFinished: {
				const rows = Helpers.parseWeatherObservations(text);
				const near = Helpers.weatherObservationCode(rows);

				if (near < 0)
					return;

				root.code = near;
				root.description = root.codeInfo.name;
				root.save();
			}
		}
	}
}
