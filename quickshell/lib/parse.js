.pragma library

function plainText(html) {
	return String(html || "")
		.replace(/<br\s*\/?>/gi, " ")
		.replace(/<[^>]*>/g, "")
		.replace(/&lt;/g, "<")
		.replace(/&gt;/g, ">")
		.replace(/&quot;/g, "\"")
		.replace(/&#39;/g, "'")
		.replace(/&nbsp;/g, " ")
		.replace(/&amp;/g, "&")
		.replace(/\s+/g, " ")
		.trim();
}

function pathLines(text) {
	return String(text || "").split("\n").map(function (line) { return line.trim(); }).filter(function (line) { return line !== ""; });
}

function parseClipboardList(text) {
	const entries = [];

	String(text || "").split("\n").forEach(function (line) {
		const tab = line.indexOf("\t");

		if (tab <= 0)
			return;

		const id = line.substring(0, tab).trim();
		const preview = line.substring(tab + 1).trim();

		if (id !== "" && preview !== "")
			entries.push({ id: id, text: preview });
	});

	return entries;
}

function calculate(expression) {
	const text = String(expression === undefined || expression === null ? "" : expression).replace(/\s+/g, "");

	if (!text)
		return null;

	const constants = { pi: Math.PI, e: Math.E };
	const functions = { sqrt: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil };
	let at = 0;

	function eat(character) {
		if (text[at] === character) {
			at += 1;
			return true;
		}

		return false;
	}

	function parseExpression() {
		let value = parseTerm();

		if (value === null)
			return null;

		for (;;) {
			if (eat("+")) {
				const right = parseTerm();

				if (right === null)
					return null;
				value += right;
			} else if (eat("-")) {
				const right = parseTerm();

				if (right === null)
					return null;
				value -= right;
			} else
				return value;
		}
	}

	function parseTerm() {
		let value = parsePower();

		if (value === null)
			return null;

		for (;;) {
			if (eat("*")) {
				const right = parsePower();

				if (right === null)
					return null;
				value *= right;
			} else if (eat("/")) {
				const right = parsePower();

				if (right === null || right === 0)
					return null;
				value /= right;
			} else if (eat("%")) {
				const right = parsePower();

				if (right === null || right === 0)
					return null;
				value %= right;
			} else
				return value;
		}
	}

	function parsePower() {
		const base = parseUnary();

		if (base === null)
			return null;
		if (!eat("^"))
			return base;

		const exponent = parsePower();

		return exponent === null ? null : Math.pow(base, exponent);
	}

	function parseUnary() {
		if (eat("-")) {
			const value = parseUnary();

			return value === null ? null : -value;
		}
		if (eat("+"))
			return parseUnary();

		return parseAtom();
	}

	function parseAtom() {
		if (eat("(")) {
			const value = parseExpression();

			return value === null || !eat(")") ? null : value;
		}

		const word = /^[a-zA-Z]+/.exec(text.substring(at));

		if (word) {
			at += word[0].length;

			if (eat("(")) {
				const argument = parseExpression();

				if (argument === null || !eat(")") || !functions[word[0]])
					return null;

				return functions[word[0]](argument);
			}

			return constants[word[0]] === undefined ? null : constants[word[0]];
		}

		const number = /^[0-9]*\.?[0-9]+/.exec(text.substring(at));

		if (!number)
			return null;

		at += number[0].length;

		return parseFloat(number[0]);
	}

	const result = parseExpression();

	if (result === null || at !== text.length || !isFinite(result))
		return null;

	return result;
}

function formatNumber(value) {
	if (value === null || value === undefined || !isFinite(value))
		return "";

	return String(Math.round(value * 1000000) / 1000000);
}

function calcEntry(query) {
	const text = String(query === undefined || query === null ? "" : query).trim();

	if (!/[0-9]/.test(text))
		return null;

	const value = calculate(text);

	if (value === null)
		return null;

	const out = formatNumber(value);

	if (out === text)
		return null;

	return { id: "calc", kind: "calc", name: text + " = " + out, keywords: [], value: out };
}
