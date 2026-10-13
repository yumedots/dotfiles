.pragma library

function quotePath(arg) {
	return "'" + String(arg).replace(/'/g, "'\\''") + "'";
}

function fileMeanCommand(path, screenW, screenH, barH) {
	const geo = Math.max(1, Math.round(screenW)) + "x" + Math.max(1, Math.round(screenH));
	const strip = Math.max(1, Math.round(screenW)) + "x" + Math.max(1, Math.round(barH));

	return ["sh", "-c", "magick " + quotePath(path) + " -resize " + geo + "^ -gravity center -extent " + geo + " -crop " + strip + "+0+0 +repage -colorspace Gray -format \"%[fx:mean]\" info:"];
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

function settleInk(mean, current) {
	if (current === "black")
		return mean < 0.425 ? "white" : "black";

	return mean >= 0.575 ? "black" : "white";
}
