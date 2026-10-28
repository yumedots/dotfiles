.pragma library

function cleanName(name) {
	const value = String(name === undefined || name === null ? "" : name).trim();

	if (value.endsWith(".desktop"))
		return value.slice(0, value.length - 8);

	return value;
}

function iconNames(names) {
	const out = [];

	(names || []).forEach(function (name) {
		const value = cleanName(name);

		if (!value)
			return;

		const seen = out.some(function (other) {
			return other.toLowerCase() === value.toLowerCase();
		});

		if (!seen)
			out.push(value);
	});

	return out;
}
