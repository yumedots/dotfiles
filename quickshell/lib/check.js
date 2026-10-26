const fs = require("fs");

const filter = process.argv[2] || "";
let ran = 0;

function assert(condition, message) {
	ran += 1;

	if (!condition)
		throw new Error(message);
}

function section(name, body) {
	if (filter === "" || name.indexOf(filter) >= 0)
		body();
}

eval(fs.readdirSync(__dirname).filter(function (name) { return name.endsWith(".js") && name !== "check.js"; }).sort().map(function (name) {
	return fs.readFileSync(__dirname + "/" + name, "utf8").replace(".pragma library", "");
}).join("\n"));

const Config = new Function(fs.readFileSync(__dirname + "/../config.js", "utf8").replace(".pragma library", "")
	+ "\nreturn { weatherActionSize: weatherActionSize, weatherCardGap: weatherCardGap, weatherCardHeaderGap: weatherCardHeaderGap, weatherCardPadding: weatherCardPadding, weatherCardWidth: weatherCardWidth, weatherCodes: weatherCodes, weatherCoords: weatherCoords, weatherDayGap: weatherDayGap, weatherDayGlyphSize: weatherDayGlyphSize, weatherDayLabelSize: weatherDayLabelSize, weatherDayTempSize: weatherDayTempSize, weatherDays: weatherDays, weatherHeroGlyphSize: weatherHeroGlyphSize, weatherHeroLabelSize: weatherHeroLabelSize, weatherHeroTempSize: weatherHeroTempSize, weatherHeroUnitSize: weatherHeroUnitSize, weatherHeroUnitTop: weatherHeroUnitTop, weatherHeroValueSize: weatherHeroValueSize, weatherIcon: weatherIcon, weatherLoadingIcon: weatherLoadingIcon, weatherLocation: weatherLocation, weatherPlaceSize: weatherPlaceSize, weatherSeparator: weatherSeparator, weatherSeparatorColor: weatherSeparatorColor, weatherStationCount: weatherStationCount, weatherTempUnit: weatherTempUnit, weatherWindUnit: weatherWindUnit, notifyScale: notifyScale, notifyWidth: notifyWidth, notifySlot: notifySlot, notifyRowHeight: notifyRowHeight, notifyAppFontSize: notifyAppFontSize };")();

section("entries", function () {
const modeConfig = {
	launcherModes: [
		{ mode: "calc", name: "Calculator", mark: "=", glyph: "C" },
		{ mode: "clipboard", name: "Clipboard", mark: "$", glyph: "K", keywords: ["copy"] }
	],
	launcherGroups: [{ id: "apps", name: "All apps", glyph: "A" }],
	launcherCommands: [{ name: "Edit shell config", command: "code-insiders ~/.config/quickshell/config.js" }],
	launcherActions: [{ name: "Shut down", command: "systemctl poweroff", glyph: "P" }],
	launcherIconCommand: "c",
	launcherIconCalc: "=",
	launcherIconWindow: "w",
	launcherIconFile: "f",
	launcherIconClipboard: "k",
	launcherIconProcess: "p",
	launcherIconFallback: "P"
};

assert(modeMarks(modeConfig.launcherModes)["clipboard"] === "$", "a mark comes back keyed by its mode");
assert(modeMarks([])["calc"] === undefined, "no modes, no marks");
assert(modeInfo("calc", modeConfig).name === "Calculator", "a mode resolves to its config");
assert(modeInfo("group:apps", modeConfig).id === "apps", "a group mode resolves to the group, not to a mode");
assert(modeInfo("nope", modeConfig) === null && modeInfo("group:nope", modeConfig) === null, "unknown modes and groups resolve to nothing");
assert(markOf("clipboard", modeConfig) === "$", "the mark of a mode is what an entry types");
assert(markOf("nope", modeConfig) === "" && markOf("group:apps", modeConfig) === "", "groups and unknown modes have no mark");

const modeList = modeEntries(modeConfig.launcherModes);
assert(modeList[0].id === "mode:calc" && modeList[0].kind === "mode" && modeList[0].mode === "calc", "a mode entry names the mode it opens");
assert(modeList[1].keywords[0] === "copy" && modeList[0].keywords.length === 0, "keywords are optional");
assert(groupEntries(modeConfig.launcherGroups)[0].id === "group:apps" && groupEntries(modeConfig.launcherGroups)[0].group === "apps", "a group entry names the group it opens");

const footApps = {
	footclient: { name: "Foot Client", exec: "footclient", execLine: "footclient" },
	foot: { name: "Foot", exec: "foot", execLine: "foot" },
	"foot-server": { name: "Foot Server", exec: "foot-server", execLine: "foot-server" },
	btop: { name: "btop", exec: "btop", execLine: "btop" }
};
const folded = appEntries(footApps, [], { foot: ["foot", "footclient", "foot-server"] });

assert(folded.length === 2, "the foot variants fold into one entry");
assert(folded[0].kind === "app" && folded[0].name === "foot", "the survivor is named after the alias key");
assert(folded.map(function (entry) { return entry.appId; }).indexOf("footclient") < 0, "the other variants are gone");
assert(appEntries({ footclient: footApps.footclient }, [], { foot: ["foot", "footclient"] })[0].name === "foot", "a lone variant is renamed too");
assert(appEntries(footApps, [], {}).length === 4, "without aliases every app stays");
assert(appEntries(footApps, ["btop"], {}).length === 3, "ignored apps stay ignored");
assert(appEntries({ broken: { name: "Broken" } }, [], {}).length === 0, "an entry without an exec is skipped");

const saved = customEntries("htop\thtop -d 5\nnotes\n\nvt\tfootclient -e vt");
assert(saved.length === 3, "blank lines are not saved entries");
assert(saved[0].id === "saved:htop" && saved[0].kind === "saved" && saved[0].command === "htop -d 5", "a saved entry keeps its command");
assert(saved[1].command === "notes", "a line with no command runs itself");
assert(formatCustom(saved) === "htop\thtop -d 5\nnotes\tnotes\nvt\tfootclient -e vt", "and writes back in the same shape");
assert(formatCustom(customEntries(formatCustom(saved))) === formatCustom(saved), "the cache round trips");
assert(customEntries("\n  \n").length === 0, "a cache of blank lines is empty");
assert(toggleCustom([], "  htop  ")[0].name === "htop", "saving trims the query");
assert(toggleCustom(saved, "htop").length === 2, "saving the same query again unsaves it");
assert(toggleCustom(saved, "").length === 3, "an empty query saves nothing");
assert(toggleCustom(saved, "btop").length === 4 && toggleCustom(saved, "btop")[3].name === "btop", "a new entry is appended");

assert(glyphOf({ kind: "action", glyph: "P" }, modeConfig) === "P", "an entry with a glyph keeps it");
assert(glyphOf({ kind: "command" }, modeConfig) === "c", "a command falls back to the command glyph");
assert(glyphOf({ kind: "saved" }, modeConfig) === "c", "so does a saved entry");
assert(glyphOf({ kind: "file" }, modeConfig) === "f" && glyphOf({ kind: "clip" }, modeConfig) === "k", "files and clips have their own");
assert(glyphOf({ kind: "proc" }, modeConfig) === "p", "so do process rows");
assert(glyphOf({ kind: "mode" }, modeConfig) === "" && glyphOf(null, modeConfig) === "", "a mode carries its glyph from the config, nothing invents one");
assert(rememberable({ kind: "saved" }) && rememberable({ kind: "app" }) && !rememberable({ kind: "mode" }) && !rememberable({ kind: "group" }), "usage counts what gets launched, not what navigates");

const everything = all(modeConfig, appEntries(footApps, [], {}), saved);
assert(everything.length === 2 + 1 + saved.length + 1 + 4, "every source contributes its entries once");
assert(everything[0].kind === "mode" && everything[1].kind === "mode" && everything[2].kind === "group" && everything[5].kind === "saved" && everything[6].kind === "command" && everything[7].kind === "app", "and in the order modes, groups, saved, commands, apps");

const homeState = {
	files: [],
	clips: [],
	windows: [],
	entries: [{ id: "app:firefox", kind: "app", name: "Firefox" }, { id: "act:Shut down", kind: "action", name: "Shut down" }],
	groups: { apps: [{ id: "app:firefox", kind: "app", name: "Firefox" }] },
	pins: [],
	usage: {},
	calc: null
};

assert(results("", "", homeState).length === 1, "the home list keeps the actions and hides the apps");
assert(results("", "", { files: [], clips: [], windows: [], entries: homeState.entries, groups: homeState.groups, pins: ["app:firefox"], usage: {}, calc: null }).length === 2, "a pinned app stays on the home list");
assert(results("", "fire", homeState).length === 1, "typing still finds an app");
assert(results("group:apps", "", homeState).length === 1, "a group mode lists its own contents instead");
assert(results("group:apps", "s", homeState).length === 0 && results("group:apps", "fire", homeState).length === 1, "and ranks inside the group");
assert(results("group:nope", "", homeState).length === 0, "an unknown group is empty, not a crash");

const calcOnly = { files: [], clips: [], windows: [], entries: [], groups: {}, pins: [], usage: {}, calc: { id: "calc:1+1", kind: "calc", name: "1+1", value: "2" } };

assert(results("calc", "1+1", calcOnly).length === 1 && results("calc", "1+1", calcOnly)[0].kind === "calc", "calc mode shows the calculator row and nothing else");
assert(results("calc", "111", { files: [], clips: [], windows: [], entries: [], groups: {}, pins: [], usage: {}, calc: null }).length === 0, "and nothing when the query does not parse");
});

section("ranking", function () {
const ranked = rankEntries([
	{ id: "app:a", name: "Alpha" },
	{ id: "app:b", name: "Bravo" },
	{ id: "app:c", name: "Charlie" }
], "", ["app:c"], { "app:b": { count: 4, last: 10 } });
assert(ranked[0].id === "app:c", "a pinned entry sorts first");
assert(ranked[1].id === "app:b", "then the most used one");
assert(ranked[2].id === "app:a", "the rest stay in name order");
assert(rankEntries([{ id: "app:a", name: "Alpha" }], "zzz", [], {}).length === 0, "nothing matches, nothing listed");
assert(rankEntries([{ id: "app:a", name: "Alpha" }], "", [], {})[0].id === "app:a", "an empty query keeps everything");

const powerRows = [{ id: "app:x", kind: "app", name: "X" }, { id: "act:Shut down", kind: "action", name: "Shut down" }];
assert(rankEntries(powerRows, "", [], { "act:Shut down": { count: 18, last: 99 } })[0].id === "app:x", "a power action never outranks a plain entry, however often it was used");
assert(rankEntries(powerRows, "", [], {})[0].id === "app:x", "and not with nothing used at all");
assert(rankEntries(powerRows, "shut", [], {})[0].id === "act:Shut down", "a power action is still the match when it is what you type");

const usage = parseUsage("app:a\t3\t100\napp:b\t1\nbroken\n");
assert(usage["app:a"].count === 3 && usage["app:a"].last === 100, "usage counts and times parse");
assert(usage["app:b"].last === 0, "a missing timestamp is zero");
assert(Object.keys(usage).length === 2, "a broken line is dropped");
assert(Object.keys(parseUsage("")).length === 0, "an empty usage file has no entries");
assert(formatUsage({ "app:b": { count: 1, last: 2 }, "app:a": { count: 3, last: 4 } }) === "app:a\t3\t4\napp:b\t1\t2", "usage writes back, sorted by id");
assert(formatUsage({ a: { count: 1, last: 1 }, b: { count: 1, last: 5 }, c: { count: 1, last: 3 } }, 2) === "b\t1\t5\nc\t1\t3", "usage is capped, the most recent entries are kept");
assert(formatUsage({ a: { count: 1, last: 1 } }, 2) === "a\t1\t1", "a usage file under the cap is kept whole");
assert(formatUsage({ a: { count: 9, last: 5 }, b: { count: 1, last: 5 } }, 1) === "a\t9\t5", "the cap falls back to the count when the times tie");
assert(Object.keys(parseUsage(formatUsage({ a: { count: 2, last: 7 } }, 10))).length === 1, "a capped file still parses back");
assert(bumpUsage({ "app:a": { count: 3, last: 100 } }, "app:a", 200)["app:a"].count === 4, "a launch bumps the count");
assert(bumpUsage({ "app:a": { count: 3, last: 100 } }, "app:a", 200)["app:a"].last === 200, "and the time");
assert(bumpUsage({}, "app:b", 5)["app:b"].count === 1, "a first launch starts at one");

});

console.log("check ok (" + ran + " assertions)");
