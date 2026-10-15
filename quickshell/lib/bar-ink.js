.pragma library

function quotePath(arg) {
	return "'" + String(arg).replace(/'/g, "'\\''") + "'";
}

function wallScanCommand(dir, depth) {
	const images = quotePath("\\.(jpg|jpeg|png|webp|gif|bmp|avif)$");

	return ["sh", "-c", "find " + quotePath(dir) + " -maxdepth " + depth
		+ " \\( -name node_modules -o -name .git \\) -prune -o -type f -printf '%T@\\t%p\\n' 2>/dev/null | grep -iE " + images + " | sort"];
}

function parseList(text) {
	const files = [];

	String(text || "").split("\n").forEach(function (line) {
		const tab = line.indexOf("\t");

		if (tab > 0 && tab < line.length - 1)
			files.push({ mtime: line.slice(0, tab), path: line.slice(tab + 1) });
	});

	return files;
}

function inkCommand(bin, path, w, h, barPx) {
	return [String(bin), "ink", String(path), "--width", String(w), "--height", String(h), "--band", String(barPx)];
}

function keyFor(path, mtime, w, h, barPx) {
	return String(path) + "|" + String(mtime) + "@" + w + "x" + h + "x" + barPx;
}

function fileOf(key) {
	return key.slice(0, key.lastIndexOf("@"));
}

function isInk(value) {
	return value === "black" || value === "white";
}

function parseInk(text) {
	const word = String(text || "").trim().split(/\s+/)[0];

	return isInk(word) ? word : "";
}

function queryInk(text, name) {
	const prefix = String(name) + ": ";
	const lines = String(text || "").split("\n");

	for (let i = 0; i < lines.length; i++) {
		if (lines[i].slice(0, prefix.length) !== prefix)
			continue;

		const at = lines[i].lastIndexOf("ink: ");

		if (at < 0)
			return "";

		const word = lines[i].slice(at + 5).trim().split(/\s+/)[0];

		return isInk(word) ? word : "";
	}

	return "";
}
