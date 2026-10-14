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

function fileMeanCommand(path, w, h, barPx) {
	const pct = Math.max(1, Math.min(100, barPx / h * 100)).toFixed(2);
	const size = w + "x" + h;

	return ["magick", String(path), "-resize", size + "^", "-gravity", "center", "-extent", size,
		"-gravity", "northwest", "-colorspace", "Gray", "-crop", "100%x" + pct + "%+0+0", "+repage",
		"-format", "%[fx:mean]", "info:"];
}

function keyFor(path, mtime, w, h, barPx) {
	return String(path) + "|" + String(mtime) + "@" + w + "x" + h + "x" + barPx;
}

function fileOf(key) {
	return key.slice(0, key.lastIndexOf("@"));
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
