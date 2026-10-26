.pragma library

function shellQuote(arg) {
	return "'" + arg.replace(/'/g, "'\\''") + "'";
}

function readCommand(path) {
	return ["sh", "-c", "cat " + shellQuote(path) + " 2>/dev/null"];
}

function writeCommand(path, text) {
	const dir = path.substring(0, path.lastIndexOf("/"));
	const make = dir ? "mkdir -p " + shellQuote(dir) + " && " : "";

	return ["sh", "-c", make + "printf '%s' " + shellQuote(text) + " > " + shellQuote(path)];
}

function readJson(text, fallback) {
	try {
		return JSON.parse(text);
	} catch (error) {
		return fallback;
	}
}

