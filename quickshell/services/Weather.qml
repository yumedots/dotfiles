pragma Singleton

import QtQuick
import Quickshell
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
	property var daily: []
	property real lat: 0
	property real lon: 0
	property int code: -1
	property var stations: []
	property bool placeFailed: false
	property real fetched: 0
	property bool loading: false
	property string status: ""
	property var places: []
	property int index: 0
	property var suggestions: []
	property var coords: ({})
	property string watching: ""

	readonly property string dir: Quickshell.shellDir + "/cache/weather"
	readonly property string placeFile: root.dir + "/place"
	readonly property string tracked: root.places[root.index] || ""
	readonly property string wanted: root.tracked !== "" ? root.tracked : Config.weatherLocation
	readonly property string cacheFile: root.dir + "/current.json"
	readonly property var codeInfo: Forecast.weatherCodeInfo(root.code, Config.weatherCodes, Config.weatherIcon)
	readonly property string icon: root.codeInfo.glyph
	readonly property var focused: slotRepeater.count > root.index ? slotRepeater.itemAt(root.index) : null
	readonly property string focusedPlace: String(root.places[root.index] || "").split(",")[0].trim()
	readonly property bool fresh: root.focused !== null && root.focused.temp !== ""
	readonly property int shownCode: root.fresh ? root.focused.code : root.code
	readonly property int primaryCode: root.shownCode
	readonly property string primaryIcon: Forecast.weatherCodeInfo(root.shownCode, Config.weatherCodes, Config.weatherIcon).glyph
	readonly property var days: root.focused && root.focused.days && root.focused.days.length > 0 ? root.focused.days : root.daily
	readonly property var current: ({
		temp: root.fresh ? root.focused.temp : root.temp,
		feels: root.fresh ? root.focused.feels : root.feels,
		wind: root.fresh ? root.focused.wind : root.wind,
		humidity: root.fresh ? root.focused.humidity : root.humidity,
		code: root.shownCode,
		icon: root.primaryIcon,
		description: root.fresh ? root.focused.description : root.description,
		place: root.focusedPlace !== "" ? root.focusedPlace : String(root.place || "").split(",")[0].trim(),
		loading: (root.fresh ? root.focused.temp : root.temp) === ""
	})

	function adopt(cached) {
		const place = cached.place || "";

		if (place !== "" && root.wanted !== "" && place !== root.wanted)
			return false;

		if (cached.unit !== Config.weatherTempUnit)
			return false;

		root.description = cached.description || "";
		root.location = cached.location || "";
		root.place = place;
		root.temp = cached.temp || "";
		root.feels = cached.feels || "";
		root.wind = cached.wind || "";
		root.humidity = cached.humidity || "";
		root.daily = cached.daily || [];
		root.lat = cached.lat || 0;
		root.lon = cached.lon || 0;
		root.code = typeof cached.code === "number" ? cached.code : -1;
		root.stations = cached.stations || [];
		root.placeFailed = cached.placeFailed === true;
		root.fetched = cached.fetched || 0;

		return true;
	}

	function save() {
		cache.save({
			fetched: root.fetched,
			unit: Config.weatherTempUnit,
			description: root.description,
			location: root.location,
			place: root.place,
			temp: root.temp,
			feels: root.feels,
			wind: root.wind,
			humidity: root.humidity,
			daily: root.daily,
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
		if (root.wanted === "") {
			root.loading = false;
			root.status = "no location";
			root.description = "";
			root.place = "";
			root.location = "";
			root.temp = "";
			root.feels = "";
			root.wind = "";
			root.humidity = "";
			root.daily = [];
			root.stations = [];
			root.code = -1;
			root.lat = 0;
			root.lon = 0;
			return;
		}

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

	function search(query) {
		const text = String(query || "").trim();

		if (text === "") {
			root.suggestions = [];
			return;
		}

		suggest.command = Shell.curl(Forecast.weatherSuggestUrl(text));
		suggest.running = true;
	}

	function slot(at) {
		return slotRepeater.itemAt(at);
	}

	function rememberCoords(place, lat, lon) {
		root.coords = Forecast.coordsWith(root.coords, place, lat, lon);
	}

	function slots() {
		const rows = root.places.slice();

		while (rows.length < Config.weatherPlaceCount)
			rows.push("");

		return rows.slice(0, Config.weatherPlaceCount);
	}

	function store() {
		placeWrite.command = Shell.writeCommand(root.placeFile, root.slots().join("\n"));
		placeWrite.running = true;
	}

	function load(text) {
		const rows = String(text || "").split("\n").map(function (row) { return row.trim(); });

		while (rows.length < Config.weatherPlaceCount)
			rows.push("");

		for (let i = 1; i < Config.weatherPlaceCount; i++)
			rows[i] = rows[i] !== "" ? rows[i] : (Config.weatherPlaceDefaults[i - 1] || "");

		root.places = rows.slice(0, Config.weatherPlaceCount);
		root.index = root.firstFilled();
	}

	function firstFilled() {
		for (let i = 0; i < root.places.length; i++) {
			if (String(root.places[i] || "") !== "")
				return i;
		}

		return 0;
	}

	function focusPlace(at) {
		const target = root.places[at] || Config.weatherLocation;

		root.index = at;
		root.stations = [];
		root.placeFailed = false;
		root.loading = false;
		root.status = "";
		root.lat = 0;
		root.lon = 0;
		root.place = target;
		root.location = target;
		root.adoptSlot(root.slot(at));
		root.refresh(true);
	}

	function adoptSlot(slot) {
		if (!slot)
			return;

		root.code = slot.code;
		root.description = slot.description;
		root.temp = slot.temp;
		root.feels = slot.feels;
		root.wind = slot.wind;
		root.humidity = slot.humidity;
		root.daily = slot.days;
	}

	function choose(label, lat, lon) {
		if (label === "")
			return;

		const rows = root.slots();
		const target = root.slot(root.index);
		const previous = target ? target.place : "";

		rows[root.index] = label;
		root.places = rows;
		root.rememberCoords(label, lat, lon);
		root.stations = [];
		root.placeFailed = false;
		root.suggestions = [];
		root.loading = false;
		root.status = "";
		root.lat = 0;
		root.lon = 0;
		root.place = label;
		root.location = label;

		if (target) {
			target.reset();

			if (previous === label)
				target.refresh();
		}

		root.store();
		root.refresh(true);
	}

	function add(label, lat, lon) {
		if (label === "")
			return;

		const rows = root.slots();
		let at = root.index;

		for (let i = 0; i < rows.length; i++) {
			if (String(rows[i] || "") === "") {
				at = i;
				break;
			}
		}

		rows[at] = label;
		root.places = rows;
		root.rememberCoords(label, lat, lon);
		root.suggestions = [];
		root.store();
		root.focusPlace(at);
	}

	function shift(step) {
		const count = Config.weatherPlaceCount;
		const direction = step < 0 ? -1 : 1;

		for (let i = 1; i < count; i++) {
			const next = ((root.index + direction * i) % count + count) % count;

			if (String(root.places[next] || "") !== "") {
				root.focusPlace(next);
				return;
			}
		}
	}

	function observe() {
		if (Config.weatherStationCount <= 0 || root.placeFailed)
			return;

		root.watching = root.place;

		if (root.stations.length > 0) {
			observe.running = true;
			return;
		}

		points.running = true;
	}

	Component.onCompleted: placeRead.running = true

	Repeater {
		id: slotRepeater

		model: Config.weatherPlaceCount

		WeatherSlot {
			place: root.slots()[index] || ""
			known: root.coords
			primary: index === 0
		}
	}

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
			root.load(text);
			root.refresh(false);
		}
	}

	CachedFile {
		id: cache

		path: root.cacheFile
		maxAge: Config.weatherCacheMs

		onLoaded: function (data, stale) {
			if (!root.adopt(data)) {
				root.locate();
				return;
			}

			if (root.place !== root.wanted) {
				root.stations = [];
				root.placeFailed = false;
				root.lat = 0;
				root.lon = 0;
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
			root.rememberCoords(root.wanted, found.lat, found.lon);
			root.place = root.wanted;
			root.location = found.place;
			fetch.running = true;
		}
	}

	Request {
		id: fetch

		command: Shell.curl(Forecast.weatherForecastUrl(root.lat, root.lon, Config.weatherTempUnit, Config.weatherWindUnit, Config.weatherDays))

		onDone: function (text) {
			const parsed = Forecast.parseWeatherCurrent(text, Config.weatherTempUnit);

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
			root.daily = Forecast.parseWeatherDaily(text, Config.weatherTempUnit);
			root.fetched = Date.now();
			root.status = "";
			root.save();
			root.observe();
		}
	}

	Request {
		id: suggest

		onDone: function (text) {
			root.suggestions = Forecast.parseWeatherSuggestions(text);
		}
	}

	Request {
		id: placeWrite
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
			if (root.watching !== root.place)
				return;

			const rows = Forecast.parseWeatherObservations(text);
			const near = Forecast.weatherObservationCode(rows);

			if (near < 0)
				return;

			root.code = near;
			root.description = root.codeInfo.name;

			if (root.focused && root.focused.place !== "" && root.focused.place === root.place)
				root.focused.stationCode = near;

			root.save();
		}
	}
}
