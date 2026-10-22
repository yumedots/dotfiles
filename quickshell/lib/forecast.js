.pragma library

function weatherGeoUrl(place) {
	const city = String(place || "").split(",")[0].trim();

	return "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(city) + "&count=8&language=en&format=json";
}

function weatherRegion(place) {
	const parts = String(place || "").split(",");

	return parts.length > 1 ? parts.slice(1).join(",").trim() : "";
}

function parseWeatherGeo(text, region) {
	let data = null;

	try {
		data = JSON.parse(text);
	} catch (error) {
		data = null;
	}

	const list = (data && data.results) || [];

	if (list.length === 0)
		return null;

	const want = String(region || "").toLowerCase();
	let hit = list[0];

	if (want !== "") {
		for (let i = 0; i < list.length; i++) {
			const row = list[i];
			const area = String(row.admin1 || "").toLowerCase();
			const country = String(row.country || "").toLowerCase();
			const code = String(row.country_code || "").toLowerCase();

			if (area.indexOf(want) === 0 || area === want || country.indexOf(want) === 0 || code === want) {
				hit = row;
				break;
			}
		}
	}

	return {
		lat: hit.latitude,
		lon: hit.longitude,
		place: [hit.name, hit.admin1].filter(function (part) { return part; }).join(", ")
	};
}

function weatherSuggestUrl(query) {
	return "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(String(query || "").trim()) + "&count=20&language=en&format=json";
}

function parseWeatherSuggestions(text) {
	let data = null;

	try {
		data = JSON.parse(text);
	} catch (error) {
		data = null;
	}

	const rows = ((data && data.results) || [])
		.filter(function (row) { return String(row.feature_code || "").indexOf("PPL") === 0; })
		.map(function (row) {
			return {
				name: row.name,
				label: [row.name, row.admin1, row.country].filter(function (part) { return part; }).join(", "),
				lat: row.latitude,
				lon: row.longitude,
				population: Number(row.population) || 0
			};
		});

	rows.sort(function (a, b) { return b.population - a.population; });

	return rows;
}

function parseCoords(text) {
	const match = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/.exec(String(text || ""));

	return match ? { lat: parseFloat(match[1]), lon: parseFloat(match[2]) } : null;
}

function coordsWith(map, place, lat, lon) {
	const key = String(place || "").trim().toLowerCase();

	if (key === "" || !lat || !lon)
		return map;

	const next = Object.assign({}, map);

	next[key] = { lat: lat, lon: lon };
	return next;
}

function coordsFor(map, place) {
	const row = (map || {})[String(place || "").trim().toLowerCase()];

	return row ? row : { lat: 0, lon: 0 };
}

function weatherForecastUrl(lat, lon, tempUnit, windUnit, days) {
	const temp = String(tempUnit || "celsius");
	const wind = String(windUnit || "kmh");
	const count = Number(days) > 0 ? Number(days) : 7;

	return "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
		+ "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,precipitation"
		+ "&daily=weather_code,temperature_2m_max,temperature_2m_min,apparent_temperature_max,apparent_temperature_min,wind_speed_10m_max,relative_humidity_2m_mean"
		+ "&temperature_unit=" + temp + "&wind_speed_unit=" + wind + "&forecast_days=" + count + "&timezone=auto";
}

function parseWeatherCurrent(text) {
	let data = null;

	try {
		data = JSON.parse(text);
	} catch (error) {
		data = null;
	}

	const current = data && data.current;

	if (!current || typeof current.weather_code !== "number")
		return null;

	const units = data.current_units || {};
	const unit = String(units.temperature_2m || "°C").replace(/\s/g, "");
	const windUnit = String(units.wind_speed_10m || "km/h");

	return {
		code: Math.round(current.weather_code),
		precip: Number(current.precipitation) || 0,
		temp: Math.round(current.temperature_2m) + unit,
		feels: Math.round(current.apparent_temperature) + unit,
		wind: Math.round(current.wind_speed_10m) + " " + windUnit,
		humidity: Math.round(current.relative_humidity_2m) + "%"
	};
}

function weatherDayLabel(date) {
	const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(date || "").trim());

	if (!match)
		return "";

	const year = Number(match[1]);
	const month = Number(match[2]);
	const day = Number(match[3]);

	if (month < 1 || month > 12 || day < 1 || day > 31)
		return "";

	const stamp = new Date(Date.UTC(year, month - 1, day));

	if (isNaN(stamp.getTime()))
		return "";

	if (stamp.getUTCFullYear() !== year || stamp.getUTCMonth() !== month - 1 || stamp.getUTCDate() !== day)
		return "";

	return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][stamp.getUTCDay()];
}

function parseWeatherDaily(text) {
	let data = null;

	try {
		data = JSON.parse(text);
	} catch (error) {
		data = null;
	}

	const daily = data && data.daily;

	if (!daily || !Array.isArray(daily.time))
		return [];

	const times = daily.time;
	const fields = ["weather_code", "temperature_2m_max", "temperature_2m_min", "apparent_temperature_max", "wind_speed_10m_max", "relative_humidity_2m_mean"];

	for (let f = 0; f < fields.length; f++) {
		const values = daily[fields[f]];

		if (!Array.isArray(values) || values.length < times.length)
			return [];
	}

	const units = data.daily_units || {};
	const currentUnits = data.current_units || {};
	const unit = String(units.temperature_2m_max || currentUnits.temperature_2m || "°C").replace(/\s/g, "");
	const windUnit = String(units.wind_speed_10m_max || currentUnits.wind_speed_10m || "km/h");
	const rows = [];

	for (let i = 0; i < times.length; i++) {
		const date = String(times[i]);

		rows.push({
			date: date,
			day: weatherDayLabel(date),
			code: Math.round(Number(daily.weather_code[i]) || 0),
			tempMax: Math.round(Number(daily.temperature_2m_max[i])) + unit,
			tempMin: Math.round(Number(daily.temperature_2m_min[i])) + unit,
			feels: Math.round(Number(daily.apparent_temperature_max[i])) + unit,
			wind: Math.round(Number(daily.wind_speed_10m_max[i]) || 0) + " " + windUnit,
			humidity: Math.round(Number(daily.relative_humidity_2m_mean[i]) || 0) + "%"
		});
	}

	return rows;
}

function splitTemp(temp) {
	const match = /^([+-]?\d+(?:\.\d+)?)\s*(.*)$/.exec(String(temp || "").trim());

	if (!match)
		return { value: String(temp || "").trim(), unit: "" };

	return { value: match[1], unit: match[2] };
}

function weatherPointsUrl(lat, lon) {
	return "https://api.weather.gov/points/" + lat + "," + lon;
}

function weatherObservationUrl(id) {
	return "https://api.weather.gov/stations/" + id + "/observations/latest";
}

function weatherRequest(urls) {
	return "curl -sL -m 15 -H 'User-Agent: quickshell-weather (weather@example.com) ' -w '\n@@QS@@\n' " + urls;
}

function weatherBody(text) {
	return String(text || "").split("@@QS@@")[0];
}

function parseWeatherPoints(text) {
	let data = null;

	try {
		data = JSON.parse(weatherBody(text));
	} catch (error) {
		data = null;
	}

	const props = data && data.properties;

	if (!props || !props.observationStations)
		return null;

	return props.observationStations;
}

function stationDistance(lat, lon, stationLat, stationLon) {
	const dx = (stationLon - lon) * 0.9;
	const dy = stationLat - lat;

	return dx * dx + dy * dy;
}

function parseWeatherStationIds(text, lat, lon, count) {
	let data = null;

	try {
		data = JSON.parse(weatherBody(text));
	} catch (error) {
		data = null;
	}

	const rows = [];
	const feats = (data && data.features) || [];

	for (let i = 0; i < feats.length; i++) {
		const props = feats[i].properties || {};
		const coords = (feats[i].geometry || {}).coordinates || [];

		if (!props.stationIdentifier || coords.length < 2)
			continue;

		rows.push({ id: props.stationIdentifier, d: stationDistance(lat, lon, coords[1], coords[0]) });
	}

	rows.sort(function (a, b) { return a.d - b.d; });

	return rows.slice(0, count).map(function (row) { return row.id; });
}

function weatherCodeFromText(text) {
	const line = String(text || "").toLowerCase();

	if (line === "")
		return -1;

	if (line.indexOf("thunder") >= 0)
		return 95;

	if (line.indexOf("hail") >= 0)
		return 96;

	if (line.indexOf("freezing") >= 0 || line.indexOf("sleet") >= 0)
		return 66;

	if (line.indexOf("heavy rain") >= 0 || line.indexOf("heavy shower") >= 0)
		return 65;

	if (line.indexOf("rain") >= 0 || line.indexOf("drizzle") >= 0 || line.indexOf("shower") >= 0)
		return 61;

	if (line.indexOf("heavy snow") >= 0 || line.indexOf("blizzard") >= 0)
		return 75;

	if (line.indexOf("snow") >= 0)
		return 71;

	if (line.indexOf("fog") >= 0 || line.indexOf("mist") >= 0 || line.indexOf("haze") >= 0)
		return 45;

	if (line.indexOf("partly") >= 0 || line.indexOf("mostly sunny") >= 0 || line.indexOf("mostly clear") >= 0)
		return 2;

	if (line.indexOf("overcast") >= 0 || line.indexOf("cloudy") >= 0)
		return 3;

	if (line.indexOf("clear") >= 0 || line.indexOf("sunny") >= 0)
		return 0;

	return -1;
}

function parseWeatherObservations(text) {
	const chunks = String(text || "").split("@@QS@@");
	const rows = [];

	for (let i = 0; i < chunks.length; i++) {
		let data = null;

		try {
			data = JSON.parse(chunks[i]);
		} catch (error) {
			data = null;
		}

		const props = data && data.properties;

		if (!props || !props.textDescription)
			continue;

		rows.push({
			text: props.textDescription,
			code: weatherCodeFromText(props.textDescription),
			precip: ((props.precipitationLastHour || {}).value) || 0
		});
	}

	return rows;
}

function weatherObservationCode(rows) {
	let first = -1;

	for (let i = 0; i < rows.length; i++) {
		const row = rows[i];

		if (row.code >= 51)
			return row.code;

		if (row.precip > 0)
			return 61;

		if (first < 0)
			first = row.code;
	}

	return first;
}

function weatherCodeFor(code, precip) {
	if (precip > 0 && code <= 48)
		return 61;

	return code;
}

function weatherCodeInfo(code, table, fallback) {
	const row = (table || {})[code];

	if (row)
		return row;

	return { name: "", glyph: fallback || "" };
}
