.pragma library

function barLayoutDefault() {
	return {
		position: "top",
		transparent: false,
		centerAnchor: "clock",
		left: [{ id: "workspaces" }],
		center: [{ id: "clock" }],
		right: [{ id: "tray" }, { id: "notify" }, { id: "cpu" }, { id: "memory" }, { id: "volume" }, { id: "github" }]
	};
}

function parseBarLayout(text) {
	const fallback = barLayoutDefault();
	let data;

	try {
		data = JSON.parse(String(text === undefined || text === null ? "" : text));
	} catch (error) {
		return fallback;
	}

	const bar = data && data.bar ? data.bar : {};
	const layout = bar.layout ? bar.layout : {};
	const slot = function (name) {
		const list = layout[name];

		if (!Array.isArray(list))
			return fallback[name];

		return list.filter(function (entry) { return entry && typeof entry.id === "string" && entry.id !== ""; });
	};

	return {
		position: bar.position === "bottom" ? "bottom" : "top",
		transparent: bar.transparent === true,
		centerAnchor: typeof bar.centerAnchor === "string" ? bar.centerAnchor : fallback.centerAnchor,
		left: slot("left"),
		center: slot("center"),
		right: slot("right")
	};
}
