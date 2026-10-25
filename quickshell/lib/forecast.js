.pragma library

function weatherCodeInfo(code, table, fallback) {
	const row = (table || {})[code];

	if (row)
		return row;

	return { name: "", glyph: fallback || "" };
}

function splitTemp(temp) {
	const match = /^([+-]?\d+(?:\.\d+)?)\s*(.*)$/.exec(String(temp || "").trim());

	if (!match)
		return { value: String(temp || "").trim(), unit: "" };

	return { value: match[1], unit: match[2] };
}
