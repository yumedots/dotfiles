.pragma library

function shellQuote(arg) {
	return "'" + arg.replace(/'/g, "'\\''") + "'";
}

function curl(url, seconds) {
	return ["sh", "-c", "curl -s -m " + (seconds > 0 ? Math.round(seconds) : 15) + " " + shellQuote(url)];
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

function fileSearchCommand(home, query, depth, max, skip) {
	const skipNames = skip || [];
	const prune = skipNames.map(function (name) { return "-name " + shellQuote(name); }).join(" -o ");
	const inside = (prune ? "\\( " + prune + " \\) -prune -o " : "") + "-iname " + shellQuote("*" + query + "*") + " -print";

	return ["sh", "-c", "find " + shellQuote(home) + " -maxdepth " + Math.max(1, Math.floor(depth)) + " "
		+ inside + " 2>/dev/null | head -n " + Math.max(1, Math.floor(max))];
}
