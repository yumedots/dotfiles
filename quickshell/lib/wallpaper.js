.pragma library

const extensions = [".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif"];

function lastValue(source, key) {
	const pattern = new RegExp("(?:^|\\n)[ \\t]*(?:local[ \\t]+)?" + key + "[ \\t]*=[ \\t]*[\"']([^\"'\\n]+)[\"']", "g");
	let match;
	let found = null;

	while ((match = pattern.exec(source)) !== null)
		found = match[1];

	return found;
}

function dirFromText(source) {
	return lastValue(String(source === undefined || source === null ? "" : source), "wallpaperDir");
}

function wallpaperFromText(source) {
	return lastValue(String(source === undefined || source === null ? "" : source), "wallpaper");
}

function nameOf(path) {
	const text = String(path === undefined || path === null ? "" : path);
	const base = text.substring(text.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "");

	return base.replace(/[-_]+/g, " ").trim() || base;
}

function supported(path) {
	const text = String(path === undefined || path === null ? "" : path).toLowerCase();

	return extensions.indexOf(text.substring(text.lastIndexOf("."))) >= 0;
}

function thumbName(path) {
	const text = String(path);
	const base = text.substring(text.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "").replace(/[^\w-]+/g, "_");
	let hash = 5381;

	for (let i = 0; i < text.length; i++)
		hash = (hash * 33 + text.charCodeAt(i)) >>> 0;

	return hash.toString(16) + "-" + base + ".jpg";
}

function thumbPath(path, dir) {
	return String(dir) + "/" + thumbName(path);
}

function thumbsFromText(text) {
	const names = {};

	String(text === undefined || text === null ? "" : text).split("\n").forEach(function (line) {
		if (line.trim() !== "")
			names[line.trim()] = true;
	});

	return names;
}

function entries(text, dir, thumbs) {
	return String(text === undefined || text === null ? "" : text)
		.split("\n")
		.map(function (line) { return line.trim(); })
		.filter(function (line) { return line !== "" && supported(line); })
		.map(function (path) {
			const thumb = dir && thumbs && thumbs[thumbName(path)] ? thumbPath(path, dir) : path;

			return { id: "wall:" + path, kind: "wallpaper", name: nameOf(path), keywords: [], path: path, preview: thumb };
		});
}

function applyCommand(path, config) {
	return [
		"awww", "img",
		"--transition-type", config.wallpaperTransition,
		"--transition-duration", String(config.wallpaperTransitionMs / 1000),
		"--transition-fps", String(config.wallpaperTransitionFps),
		path
	];
}

function settingsText(image, dir) {
	return "return {\n    wallpaper = \"" + String(image === undefined || image === null ? "" : image)
		+ "\",\n    wallpaperDir = \"" + String(dir === undefined || dir === null ? "" : dir) + "\",\n}\n";
}
