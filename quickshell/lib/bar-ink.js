.pragma library

function stripCommand(monX, monY, monW, barH) {
	const geo = Math.max(0, Math.round(monX)) + "," + Math.max(0, Math.round(monY)) + " " + Math.max(1, Math.round(monW)) + "x" + Math.max(1, Math.round(barH));

	return ["sh", "-c", "grim -g " + shellQuote(geo) + " - 2>/dev/null | magick png:- -colorspace Gray -format \"%[fx:mean]\" info:"];
}

function shellQuote(arg) {
	return "'" + String(arg).replace(/'/g, "'\\''") + "'";
}

function monitorGeo(text, name) {
	const monitors = JSON.parse(String(text || "[]"));

	for (let i = 0; i < monitors.length; i++) {
		if (monitors[i].name === name)
			return { x: monitors[i].x, y: monitors[i].y, w: monitors[i].width, h: monitors[i].height };
	}

	return null;
}

function parseMean(text) {
	const mean = Number(String(text || "").trim());

	return mean >= 0 && mean <= 1 ? mean : -1;
}

function inkFor(mean) {
	return mean >= 0.5 ? "black" : "white";
}
