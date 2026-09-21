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

function parseCoords(text) {
	const match = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/.exec(String(text || ""));

	return match ? { lat: parseFloat(match[1]), lon: parseFloat(match[2]) } : null;
}

function weatherForecastUrl(lat, lon) {
	return "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
		+ "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,precipitation"
		+ "&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto";
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

	const unit = String((data.current_units || {}).temperature_2m || "°F").replace(/\s/g, "");

	return {
		code: Math.round(current.weather_code),
		precip: Number(current.precipitation) || 0,
		temp: Math.round(current.temperature_2m) + unit,
		feels: Math.round(current.apparent_temperature) + unit,
		wind: Math.round(current.wind_speed_10m) + "mph",
		humidity: Math.round(current.relative_humidity_2m) + "%"
	};
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
