.pragma library

function quotePath(arg) {
	return "'" + String(arg).replace(/'/g, "'\\''") + "'";
}

function screenMeanCommand(name, barRatio) {
	const pct = Math.max(1, Math.min(100, barRatio * 100)).toFixed(2);

	return ["sh", "-c", "grim -o " + quotePath(name) + " - | magick png:- -colorspace Gray -crop 100%x" + pct + "%+0+0 +repage -format \"%[fx:mean]\" info:"];
}

function wallpaperForScreen(text, name) {
	const lines = String(text || "").split("\n");

	for (let i = 0; i < lines.length; i++) {
		const hit = new RegExp("^:\\s*" + name + ":\\s*\\d+x\\d+.*image:\\s*(.+?)\\s*$").exec(lines[i]);

		if (hit)
			return hit[1];
	}

	return "";
}

function parseMean(text) {
	const clean = String(text || "").trim();

	if (clean === "")
		return -1;

	const mean = Number(clean);

	return mean >= 0 && mean <= 1 ? mean : -1;
}

function inkFor(mean) {
	return mean >= 0.5 ? "black" : "white";
}
