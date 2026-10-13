.pragma library

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
