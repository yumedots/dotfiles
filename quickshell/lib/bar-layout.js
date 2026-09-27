.pragma library

function barLayoutEmpty() {
	return {
		position: "top",
		transparent: false,
		centerAnchor: "",
		left: [],
		center: [],
		right: []
	};
}

function parseBarLayout(text) {
	let data;

	try {
		data = JSON.parse(String(text === undefined || text === null ? "" : text));
	} catch (error) {
		return null;
	}

	const bar = data && typeof data === "object" && data.bar && typeof data.bar === "object" ? data.bar : {};
	const layout = bar.layout && typeof bar.layout === "object" ? bar.layout : {};
	const slot = function (name) {
		const list = layout[name];

		if (!Array.isArray(list))
			return [];

		return list.filter(function (entry) { return entry && typeof entry.id === "string" && entry.id !== ""; });
	};

	return {
		position: bar.position === "bottom" ? "bottom" : "top",
		transparent: bar.transparent === true,
		centerAnchor: typeof bar.centerAnchor === "string" ? bar.centerAnchor : "",
		left: slot("left"),
		center: slot("center"),
		right: slot("right")
	};
}
