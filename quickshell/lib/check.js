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


assert(glyphOf({ kind: "action", glyph: "P" }, modeConfig) === "P", "an entry with a glyph keeps it");
assert(glyphOf({ kind: "command" }, modeConfig) === "c", "a command falls back to the command glyph");
assert(glyphOf({ kind: "file" }, modeConfig) === "f" && glyphOf({ kind: "clip" }, modeConfig) === "k", "files and clips have their own");
assert(glyphOf({ kind: "proc" }, modeConfig) === "p", "so do process rows");
assert(glyphOf({ kind: "mode" }, modeConfig) === "" && glyphOf(null, modeConfig) === "", "a mode carries its glyph from the config, nothing invents one");


const homeState = {
	files: [],
	clips: [],
	windows: [],
	entries: [{ id: "app:firefox", kind: "app", name: "Firefox" }, { id: "act:Shut down", kind: "action", name: "Shut down" }],
	groups: { apps: [{ id: "app:firefox", kind: "app", name: "Firefox" }] },
	pins: [],
	calc: null
};



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
assert(rankEntries(powerRows, "shut", [], {})[0].id === "act:Shut down", "a power action is still the match when it is what you type");


});

console.log("check ok (" + ran + " assertions)");
