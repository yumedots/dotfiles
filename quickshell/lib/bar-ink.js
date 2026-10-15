.pragma library

function queryColor(text, name) {
	const prefix = String(name) + ": ";
	const lines = String(text || "").split("\n");

	for (let i = 0; i < lines.length; i++) {
		// each line is "namespace: name: WxH, scale: ..., ink: white (#ffffff)"
		const colon = lines[i].indexOf(": ");
		const info = colon >= 0 ? lines[i].slice(colon + 2) : lines[i];

		if (info.slice(0, prefix.length) !== prefix)
			continue;

		const at = info.lastIndexOf("ink: ");

		if (at < 0)
			return "";

		const kind = info.slice(at + 5).match(/^(white|black)\b/);

		return kind ? (kind[1] === "white" ? "#ffffff" : "#000000") : "";
	}

	return "";
}
