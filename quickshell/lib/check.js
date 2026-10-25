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
	+ "\nreturn { weatherActionSize: weatherActionSize, weatherCardGap: weatherCardGap, weatherCardHeaderGap: weatherCardHeaderGap, weatherCardPadding: weatherCardPadding, weatherCardWidth: weatherCardWidth, weatherCodes: weatherCodes, weatherCoords: weatherCoords, weatherDayGap: weatherDayGap, weatherDayGlyphSize: weatherDayGlyphSize, weatherDayLabelSize: weatherDayLabelSize, weatherDayTempSize: weatherDayTempSize, weatherDays: weatherDays, weatherHeroGlyphSize: weatherHeroGlyphSize, weatherHeroLabelSize: weatherHeroLabelSize, weatherHeroTempSize: weatherHeroTempSize, weatherHeroUnitSize: weatherHeroUnitSize, weatherHeroUnitTop: weatherHeroUnitTop, weatherHeroValueSize: weatherHeroValueSize, weatherIcon: weatherIcon, weatherLoadingIcon: weatherLoadingIcon, weatherLocation: weatherLocation, weatherPlaceSize: weatherPlaceSize, weatherSeparator: weatherSeparator, weatherSeparatorColor: weatherSeparatorColor, weatherStationCount: weatherStationCount, weatherTempUnit: weatherTempUnit, weatherWindUnit: weatherWindUnit, networkSpeedBytes: networkSpeedBytes, notifyScale: notifyScale, notifyWidth: notifyWidth, notifySlot: notifySlot, notifyRowHeight: notifyRowHeight, notifyAppFontSize: notifyAppFontSize };")();

section("apps", function () {
const entries = desktopEntries([
	{ id: "foot", name: "Foot", execString: "foot --server", command: ["foot", "--server"], icon: "foot" },
	{ id: "code-insiders", name: "Visual Studio Code - Insiders", execString: "code-insiders %F", command: ["code-insiders"], icon: "vscode-insiders", startupClass: "Code - Insiders" },
	{ id: "firefox", name: "Firefox", execString: "/usr/lib/firefox/firefox %u", command: ["/usr/lib/firefox/firefox"], icon: "firefox" },
	{ id: "foo", name: "Foo Bar", execString: "/opt/Foo Bar/foo", command: ["/opt/Foo Bar/foo"], icon: "foo", runInTerminal: true }
]);

assert(lookupApp(entries, "firefox").icon === "firefox", "id lookup");
assert(lookupApp(entries, "firefox").exec === "firefox", "exec basename comes from the first token only");
assert(lookupApp(entries, "Code - Insiders").id === "code-insiders", "wmclass lookup");
assert(lookupApp(entries, "code-insiders").icon === "vscode-insiders", "the icon of the entry comes through");
assert(lookupApp(entries, "foo bar").id === "foo", "display name lookup");
assert(lookupApp(entries, "foo").terminal === true, "Terminal=true is parsed");
assert(lookupApp(entries, "code-insiders").id === "code-insiders", "an id with a dash is found exactly");
assert(lookupApp({ "org.vinegarhq.Sober": { id: "org.vinegarhq.Sober", name: "Sober", icon: "org.vinegarhq.Sober" } }, "org.vinegarhq.Sober").name === "Sober", "a mixed case id is found");
assert(lookupApp({ "com.spotify.Client": { id: "com.spotify.Client", name: "Spotify", icon: "com.spotify.Client" } }, "com.spotify.client").name === "Spotify", "a mixed case id is found from a lowercase query too");
assert(lookupApp({ skyrim: { id: "skyrim", name: "Skyrim", icon: "steam_icon_489830" } }, "steam_app_489830").id === "skyrim", "a window class matches its launcher entry through the icon number");
assert(lookupApp({ skyrim: { id: "skyrim", name: "Skyrim", icon: "steam_icon_489830" } }, "steam_app_999999") === null, "a different icon number means no match");
assert(lookupApp(entries, "nope") === null, "unknown ids return null");
assert(lookupApp(entries, "") === null, "empty names return null");

assert(commandEntries([{ name: "lock", command: "hyprlock", keywords: ["l"] }])[0].id === "cmd:lock", "a command entry is keyed by its name");
assert(commandEntries([{ name: "lock", command: "hyprlock" }])[0].keywords.length === 0, "a command with no keywords still gets a keyword list");
assert(clipEntries([{ id: "42", text: "hello" }])[0].clipId === "42", "a clip entry keeps the id cliphist decodes by");
assert(clipEntries([{ id: "42", text: "hello" }])[0].id === "clip:42", "and is keyed apart from apps and files");
assert(clipEntries([{ id: "42", text: "hello" }])[0].image === false, "text previews are not images");
assert(clipEntries([{ id: "935", text: "x", kind: "image", format: "png" }])[0].image === true, "binary image previews are images");
assert(clipEntries([{ id: "935", text: "x", kind: "image", format: "png" }])[0].format === "png", "the entry keeps the image format");
assert(clipEntries([{ id: "935", text: "[[ binary data 24 KiB png 361x452 ]]", kind: "image", format: "png" }])[0].name === "Image", "image rows are labeled Image, not binary data");
assert(clipEntries([{ id: "42", text: "hello" }], { "42": "Alacritty" })[0].appId === "Alacritty", "a mapped clip knows its source app");
assert(fileEntries(["/tmp/a b.txt"])[0].path === "/tmp/a b.txt", "a file entry keeps its path, spaces and all");
assert(rememberable({ kind: "app" }) && rememberable({ kind: "command" }) && rememberable({ kind: "action" }), "usage counts apps, commands and actions");
assert(!rememberable(null) && !rememberable({ kind: "window" }) && !rememberable({ kind: "file" }) && !rememberable({ kind: "clip" }) && !rememberable({ kind: "calc" }), "and never counts windows, files, clips or the calculator row");

const twoApps = [
	{ id: "app:firefox", kind: "app", name: "Firefox", keywords: ["firefox"] },
	{ id: "app:sober", kind: "app", name: "Sober", keywords: ["sober"] }
];
const calcRow = { id: "calc:1+1", kind: "calc", name: "1+1", value: "2" };
const launchState = { files: [], clips: [], windows: twoApps, entries: twoApps, pins: [], usage: {}, calc: null };

assert(results("files", "fire", { files: [{ kind: "file" }], clips: [], windows: [], entries: twoApps, pins: [], usage: {}, calc: null }).length === 1, "file mode shows the file list and nothing else");
assert(results("clipboard", "", { files: [], clips: [{ kind: "clip" }], windows: [], entries: twoApps, pins: [], usage: {}, calc: calcRow })[0].kind === "clip", "clipboard mode shows the clips, and ignores the calculator");
assert(results("windows", "", launchState).length === 2, "window mode with no query lists every window, unranked");
assert(results("windows", "sober", launchState).length === 1, "window mode with a query ranks them");
assert(results("", "sober", launchState).length === 1, "the default mode ranks the entries");
assert(results("", "zzzz", launchState).length === 0, "nothing matches nothing");
const calcState = { files: [], clips: [], windows: [], entries: twoApps, pins: [], usage: {}, calc: calcRow };

assert(results("", "sober", calcState)[0].kind === "calc", "a calculator row sits above the ranked entries");
assert(results("", "sober", calcState).length === 2 && results("", "sober", calcState)[1].kind === "app", "and takes exactly one row off the top");
});

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
assert(glyphOf({ kind: "app", appId: "noicon" }, modeConfig) === "P" && glyphOf({ kind: "window", appId: "noicon" }, modeConfig) === "w", "rows whose app has no desktop icon fall back to a nerd font glyph");
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

section("titles", function () {
assert(commandWord("btop") === "btop", "a bare command is the running program");
assert(commandWord("nvim notes.md") === "nvim", "arguments are dropped");
assert(commandWord("Zathura a.pdf") === "zathura", "the command is lowercased");
assert(commandWord("Yazi: .config") === "yazi", "a colon after the command is dropped");
assert(commandWord("gabriel@archlinux:~") === "", "a prompt title is not a command");
assert(commandWord("~/dotfiles") === "", "a path is not a command");
assert(commandWord("/usr/bin/btop") === "", "an absolute path is not a command");
assert(commandWord("") === "", "an empty title is not a command");
assert(terminalAppId("footclient", "yazi: .config", ["foot", "footclient"]) === "yazi", "a tui title wins inside a terminal");
assert(terminalAppId("footclient", "gabriel@archlinux:~", ["foot", "footclient"]) === "", "a plain prompt has no command");
assert(terminalAppId("code-insiders", "notes.md - Code", ["foot", "footclient"]) === "code-insiders", "a non-terminal keeps the class");
assert(terminalAppId("FOOTCLIENT", "btop", ["foot", "footclient"]) === "btop", "terminal classes match case-insensitively");
assert(launchCommand({ exec: "btop", terminal: true }, "btop", "footclient").join(" ") === "footclient -e sh -c btop", "a Terminal=true app opens inside the configured terminal");
assert(launchCommand({ exec: "btop", terminal: true }, "btop", "ghostty").join(" ") === "ghostty -e sh -c btop", "the terminal is exactly the one that was read");
assert(terminalName('local terminal = "footclient" -- the foot server is started at login\n') === "footclient", "the terminal comes out of the hyprland lua");
assert(terminalName('    terminal       = "footclient",\n') === "footclient", "the table entry in programs.lua is read too");
assert(terminalName("$terminal = kitty\n") === "kitty", "the legacy unquoted form is read too");
assert(terminalName("decoration = { blur = { enabled = false } }\n") === "", "a config without a terminal names nothing");
assert(terminalName("") === "", "an empty config names nothing");
assert(terminalName('local otherterminal = "x"\n') === "", "a lookalike variable is not the terminal");
assert(launchCommand({ exec: "code-insiders" }, "code-insiders").join(" ") === "sh -c code-insiders", "a regular app runs through the shell");
assert(launchCommand(null, "footclient").join(" ") === "sh -c footclient", "an entry-less app runs through the shell");
assert(launchCommand({ execLine: "helium-browser --new-window" }, "helium-browser").join(" ") === "sh -c helium-browser --new-window", "the full exec line keeps the arguments");
assert(iconFiles("/usr/share/icons/hicolor/48x48/apps/foo.png\n/usr/share/icons/hicolor/scalable/apps/foo.svg").names.foo === "/usr/share/icons/hicolor/scalable/apps/foo.svg", "the scalable icon wins");
assert(iconFiles("/usr/share/icons/hicolor/48x48/apps/bar.png\n/usr/share/icons/hicolor/256x256/apps/bar.png").names.bar === "/usr/share/icons/hicolor/256x256/apps/bar.png", "the largest bitmap wins");
assert(iconFiles("/usr/share/pixmaps/baz.xpm").names.baz === "/usr/share/pixmaps/baz.xpm", "a pixmap is kept");
assert(iconFiles("/var/lib/flatpak/exports/share/icons/hicolor/scalable/apps/org.vinegarhq.Sober.svg").names["org.vinegarhq.Sober"] !== undefined, "a dotted id keeps its dots");
assert(Object.keys(iconFiles("").names).length === 0, "an empty icon listing yields nothing");
assert(Object.keys(iconFiles("").lower).length === 0, "an empty icon listing has no lower case names either");
assert(iconLookup(iconFiles("/usr/share/pixmaps/Alacritty.svg"), "alacritty") === "/usr/share/pixmaps/Alacritty.svg", "icon lookup matches case-insensitively");
assert(iconLookup(iconFiles("/usr/share/pixmaps/Alacritty.svg"), "Alacritty") === "/usr/share/pixmaps/Alacritty.svg", "icon lookup keeps exact matches first");
assert(iconLookup(iconFiles("/usr/share/pixmaps/Alacritty.svg"), "nope") === "", "an unknown icon resolves to nothing");
assert(cleanName("Alacritty.desktop") === "Alacritty", "a desktop entry name loses its suffix");
assert(cleanName("  Alacritty  ") === "Alacritty", "a name is trimmed");
assert(cleanName("") === "", "an empty name stays empty");
assert(iconNames(["Alacritty.desktop", "alacritty", "", null]).join(",") === "Alacritty", "the names are cleaned and the repeats dropped");
assert(iconNames(["discord", "steam"]).join(",") === "discord,steam", "the names keep the order they came in");
assert(cleanExec("code-insiders %F") === "code-insiders", "field codes are stripped");
assert(cleanExec("env GDK_BACKEND=x11 firefox %u") === "env GDK_BACKEND=x11 firefox", "an env wrapper stays, only the field code goes");
assert(cleanExec("app 100%%") === "app 100%", "an escaped percent survives");
assert(cleanExec(null) === "", "a missing exec line is empty");
assert(desktopEntries([{ id: "x", execString: "/usr/bin/foo --bar %F", command: ["/usr/bin/foo", "--bar"] }]).x.execLine === "/usr/bin/foo --bar", "the exec line keeps its arguments and loses the field codes");
assert(desktopEntries([{ id: "x", execString: "\"/opt/My App/foo\" --flag", command: ["/opt/My App/foo", "--flag"] }]).x.exec === "foo", "a quoted path still yields the plain command name");
assert(Object.keys(desktopEntries()).length === 0, "a missing entry list yields nothing");
assert(togglePin([], "yazi")[0] === "yazi", "pin adds to an empty list");
assert(togglePin(["a", "b"], "c").length === 3, "pin keeps the rest");
assert(togglePin(["a", "b"], "b").length === 1, "pin removes what is pinned");
assert(togglePin(["a", "b"], "B").length === 1, "pin removal is case-insensitive");
assert(pinnedFromText("yazi\nbtop\n\n")[0] === "yazi" && pinnedFromText("yazi\nbtop\n\n").length === 2, "pin file lines are trimmed and blanks dropped");
assert(pinnedFromText("").length === 0, "a missing pin file yields nothing");
assert(shellQuote("a b") === "'a b'", "shell quoting wraps spaces");

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

section("clipboard", function () {
const listing = parseClipboardList("12\thello world\n9\tsecond entry\nnot a line\n");
assert(listing.length === 2, "every cliphist line is one entry");
assert(listing[0].id === "12" && listing[0].text === "hello world", "the cliphist id and preview are split");
assert(listing[1].text === "second entry", "the second entry is kept");
assert(parseClipboardList("").length === 0, "an empty listing has no entries");
assert(parseClipboardList("\t\n5\t\n").length === 0, "a line without a preview is dropped");
assert(parseClipboardList("935\t[[ binary data 24 KiB png 361x452 ]]")[0].kind === "image", "an image placeholder becomes an image entry");
assert(parseClipboardList("935\t[[ binary data 24 KiB png 361x452 ]]")[0].format === "png", "the placeholder keeps the image format");
assert(parseClipboardList("935\t[[ binary data 24 KiB png 361x452 ]]")[0].id === "935", "the image entry keeps the cliphist id");
assert(parseClipboardList("12\thello world")[0].kind === "text", "plain text never becomes an image entry");
assert(parseClipboardSources("935 Alacritty\n12 firefox\n")[935] === "Alacritty", "a source entry maps the cliphist id to the app");
assert(parseClipboardSources("935 Alacritty\n")[12] === undefined, "an unmapped id stays unmapped");
assert(Object.keys(parseClipboardSources("junk line\n")).length === 0, "map lines without an id are dropped");

assert(calcEntry("2+2").value === "4", "a calculation becomes a result without a prefix");
assert(calcEntry("2+2").name === "2+2 = 4", "the calculator row shows the expression and the result");
assert(calcEntry(" 1/3 ").value === "0.333333", "the expression is trimmed and rounded like the calculator");
assert(calcEntry("7") === null, "a bare number is not echoed back");
assert(calcEntry("e") === null, "a constant without a digit is not a calculation");
assert(calcEntry("2+") === null, "a broken expression has no calculator row");
assert(calcEntry("firefox") === null, "text is not a calculation");
assert(calcEntry("") === null, "an empty query has no calculator row");
assert(calcEntry("code 2") === null, "a word with a digit is not a calculation");

const find = fileSearchCommand("/home/me", "doc", 4, 30, [".git", "node_modules"])[2];
assert(find.indexOf("-maxdepth 4") > 0, "the search depth is set");
assert(find.indexOf("-iname '*doc*'") > 0, "the query becomes a glob");
assert(find.indexOf("head -n 30") > 0, "the result count is capped");
assert(find.indexOf("-name '.git'") > 0 && find.indexOf("node_modules") > 0, "heavy directories are pruned");
assert(fileSearchCommand("/home/me", "x", 3, 5, [])[2].indexOf("-prune") < 0, "with nothing to skip, nothing is pruned");
assert(fileSearchCommand("/home/me", "it's", 3, 5, [])[2].indexOf("'\\''") > 0, "a quote in the query is escaped");

assert(pathLines("/a/b\n\n/c d\n").length === 2, "blank lines are dropped from a path list");
assert(pathLines("  /a  ")[0] === "/a", "paths are trimmed");
assert(windowAppCandidates({ lastIpcObject: { class: "foot", title: "btop" } }, ["foot"]).word === "btop", "a terminal window reports the app running in it");
assert(windowAppCandidates({ lastIpcObject: { class: "helium", title: "x" } }, ["foot"]).word === "helium", "a non terminal window falls back to its class");
assert(windowAppCandidates(null, ["foot"]).className === "", "a missing window has no class");
assert(realWindows([{ lastIpcObject: null }, { lastIpcObject: { title: "Input" } }]).length === 0, "title only toplevels are helper ghosts and get dropped");
assert(realWindows([{ lastIpcObject: { workspace: "1", class: "" } }, { lastIpcObject: undefined }]).length === 1, "a window hyprland announced stays");
assert(appEntries({ firefox: { name: "Firefox", exec: "firefox" }, broken: {} }).length === 1, "an entry without a name or exec is skipped");
assert(appEntries({ firefox: { name: "Firefox", exec: "firefox" } })[0].id === "app:firefox", "the entry id is namespaced");
assert(appEntries({ avahi: { name: "Avahi", exec: "avahi" } }, ["avahi"]).length === 0, "an ignored app is skipped");
assert(appEntries({ keep: { name: "Keep", exec: "keep" } }, ["avahi"]).length === 1, "only the ignored ids are skipped");
assert(appEntries({ firefox: { name: "Firefox", exec: "firefox", execLine: "firefox --new-window" } })[0].execLine === "firefox --new-window", "the exec line reaches the launcher entry");

const steamApps = appEntries({ steam: { name: "Steam", exec: "steam" }, factorio: { name: "Factorio", exec: "steam" } }, [], {});
const steamHits = rankEntries(steamApps, "steam", [], {});

assert(steamHits.length === 1 && steamHits[0].appId === "steam", "a game launched through steam answers to its own name, not the launcher's command");
assert(rankEntries(steamApps, "factorio", [], {})[0].appId === "factorio", "the game is still found by its own name");

});

section("cpu", function () {
const statBefore = [
	"cpu  100 0 100 800 0 0 0 0 0 0",
	"cpu0 60 0 40 900 0 0 0 0 0 0",
	"cpu1 20 0 30 750 0 0 0 0 0 0",
	"intr 123 456"
].join("\n");
const statAfter = [
	"cpu  150 0 175 875 0 0 0 0 0 0",
	"cpu0 70 0 105 925 0 0 0 0 0 0",
	"cpu1 50 0 50 800 0 0 0 0 0 0"
].join("\n");

const before = parseCpuStat(statBefore);
const after = parseCpuStat(statAfter);

assert(before.total.total === 1000 && before.total.idle === 800, "the aggregate cpu line is not a core");
assert(before.cores.length === 2, "one sample per core, the other /proc/stat lines are ignored");
assert(before.cores[0].total === 1000 && before.cores[0].idle === 900, "the idle and iowait columns are the idle time");

const load = cpuPercents(before, after);
assert(load.all === 62.5, "the overall load comes from the aggregate line");
assert(load.cores[0] === 75, "a core that spent a quarter of the delta idle is at 75%");
assert(load.cores[1] === 50, "a core that spent half of the delta idle is at 50%");
assert(cpuPercents(null, after).cores[0] === 0, "the first sample has nothing to compare against");
assert(cpuPercents({ total: before.total, cores: [before.cores[0]] }, after).cores[1] === 0, "a core without a previous sample reads zero");
assert(cpuPercents(before, before).all === 0, "an unchanged sample has no load");
assert(parseCpuStat("").cores.length === 0, "an empty stat file has no cores");
assert(parseCpuStat("ctxt 1\nbtime 2\n").total.total === 0, "no cpu line, no sample");
assert(cpuLoad({ total: 200, idle: 0 }, { total: 100, idle: 50 }) === 100, "the load is clamped at 100%");

const info = parseCpuInfo([
	"processor\t: 0",
	"model name\t: Intel(R) Xeon(R) CPU E5-2690 v4 @ 2.60GHz",
	"cpu MHz\t\t: 1200.000",
	"cache size\t: 35840 KB",
	"cpu cores\t: 14",
	"processor\t: 1",
	"cpu MHz\t\t: 3196.870"
].join("\n"));

assert(info.model === "Intel(R) Xeon(R) CPU E5-2690 v4 @ 2.60GHz", "the model name is the first one");
assert(info.threads === 2 && info.cores === 14, "threads are counted, cores come from cpu cores");
assert(info.mhz === 3196.87, "the fastest clock in the file wins");
assert(info.cache === 35840, "the cache size is read in KB");
assert(cpuSpecLine(info) === "2 threads \u00b7 14 cores \u00b7 3.2 GHz \u00b7 35 MB", "the spec line reads threads, cores, clock and cache");
assert(cpuSpecLine(parseCpuInfo("")) === "", "an unreadable cpuinfo has no spec line");
assert(parseCpuInfo("processor\t: 0").cores === 1, "without a cpu cores line the thread count stands in");

});

section("processes", function () {
const processes = parseTopProcesses("90.6  4711 freebuff\n39.1  4712 freebuff\n 4.6  4713 helium\n\nnot a process\n");
assert(processes.length === 3, "one entry per ps line, the noise is dropped");
assert(processes[0].name === "freebuff" && processes[0].value === 90.6 && processes[0].pid === 4711, "the name, the pid and the value are split");
assert(parseTopProcesses("12.5 99 tmux: server")[0].name === "tmux: server", "a name with spaces survives");
assert(parseTopProcesses("12.5 99 tmux: server    /usr/bin/tmux new")[0].name === "tmux: server", "the ps comm field is padded to a fixed width");
assert(parseTopProcesses("12.5 99 tmux: server    /usr/bin/tmux new")[0].cmd === "/usr/bin/tmux new", "the command line is kept beside the name");
assert(parseTopProcesses("12.5 99 freebuff        /usr/sbin/cline --help")[0].cmd === "/usr/sbin/cline --help", "the padded command line has no leading space");
assert(parseTopProcesses("%CPU COMMAND").length === 0, "a header line is not a process");
assert(parseTopProcesses("").length === 0, "an empty listing has no processes");
assert(topProcesses(parseTopProcesses("200 9 ps\n40 8 freebuff\n10 7 ps <defunct>"), ["ps", "ps <defunct>"], 3)[0].name === "freebuff", "the sampling process and its zombie are filtered out");
assert(topProcesses(parseTopProcesses("5 4 a\n4 3 b\n3 2 c\n2 1 d"), [], 2).length === 2, "the list is capped");
assert(topProcesses(parseTopProcesses("5 1 a"), [], 0).length === 1, "a cap of zero keeps everything");
assert(topProcesses(null, [], 3).length === 0, "no processes, no list");

const beforeSort = parseTopProcesses("5.0 1 a\n4.0 2 b\n3.0 3 c");
const afterSort = parseTopProcesses("9.0 3 c\n8.0 2 b\n7.0 1 a");
const heldOrder = holdProcessOrder(beforeSort, afterSort);
assert(heldOrder.length === 3 && heldOrder[0].pid === 1 && heldOrder[2].pid === 3, "the rows keep the order they were first seen in");
assert(heldOrder[0].value === 7, "the values still come from the newest listing");
const refilled = holdProcessOrder(beforeSort, parseTopProcesses("9.0 3 c\n8.0 2 b\n6.0 4 d"));
assert(refilled.length === 3 && refilled[0].pid === 4 && refilled[1].pid === 2 && refilled[2].pid === 3, "a dead row is refilled in place, the rows below it stay put");
const survivors = holdProcessOrder(beforeSort, parseTopProcesses("9.0 3 c\n8.0 1 a"));
assert(survivors.length === 3 && survivors[0].pid === 1 && survivors[1].pid === 2 && survivors[2].pid === 3, "a vanished process keeps its row so nothing below it shifts");
const shifted = holdProcessOrder(beforeSort, parseTopProcesses("9.0 3 c\n6.0 4 d"));
assert(shifted.length === 3 && shifted[0].pid === 4 && shifted[1].pid === 2 && shifted[2].pid === 3, "the newcomer takes the top dead row, nothing below it moves");
const grown = holdProcessOrder(beforeSort, parseTopProcesses("9.0 3 c\n8.0 2 b\n7.0 1 a\n6.0 4 d\n5.0 5 e"));
assert(grown.length === 5 && grown[3].pid === 4 && grown[4].pid === 5, "with nothing dead the newcomers land at the end");
assert(holdProcessOrder([], afterSort) === afterSort, "with nothing held the list is passed through");

const searchable = parseTopProcesses("90.6 1 firefox\n10.0 2 Firefox Helper\n5.0 3 foot\n1.0 4 ps");
assert(filterProcesses(searchable, ["ps"], "fire", 10).length === 2, "the filter is a case insensitive substring match");
assert(filterProcesses(searchable, ["ps"], "FIRE", 10)[1].pid === 2, "the rows keep their pid through the filter");
assert(filterProcesses(searchable, ["ps"], "oot", 10).length === 1, "a filter only matches what contains it");
assert(filterProcesses(searchable, ["ps"], "zzz", 10).length === 0, "a filter that matches nothing returns nothing");
assert(filterProcesses(searchable, ["ps"], "ps", 10).length === 0, "the sampler stays hidden while filtering");
const scripted = parseTopProcesses("5.0 1 node            /usr/sbin/cline --help\n9.0 2 node            /usr/bin/other");
assert(filterProcesses(scripted, [], "cline", 10).length === 1, "a filter also matches the command line, not only the process name");
assert(filterProcesses(scripted, [], "cline", 10)[0].name === "node", "a command line match keeps the executable name");
assert(filterProcesses(scripted, ["node"], "cline", 10).length === 0, "the ignore list still matches on the name");
assert(filterProcesses(searchable, [], "", 2).length === 2, "an empty filter is everything, capped");
assert(filterProcesses(searchable, [], "", 0).length === 4, "a cap of zero keeps everything");
assert(filterProcesses(null, [], "x", 5).length === 0, "no processes, no matches");
assert(killCommand(4711, "-9").join(" ") === "kill -9 4711", "force quit is a kill of that pid");
assert(killCommand(4711, "-15").join(" ") === "kill -15 4711", "the signal comes from the caller");
assert(killCommand(0, "-9").length === 0, "a row without a pid is not killed");

const procRow = procEntries(parseTopProcesses("90.6  4711 freebuff        /usr/bin/freebuff\n"))[0];
assert(procRow.id === "proc:4711" && procRow.kind === "proc" && procRow.pid === 4711, "a process row is keyed by its pid and is not an app");
assert(procRow.keywords[0] === "/usr/bin/freebuff" && procRow.value === 90.6, "the command line makes it findable and the cpu share rides along");
assert(procRow.appId === "freebuff", "the process name doubles as the icon lookup key");
assert(procEntries(null).length === 0, "no processes, no rows");
assert(!rememberable(procRow), "killing a process is not something usage remembers");

});

section("mixer", function () {
	const sink = { id: 1, isSink: true, audio: { volume: 0.5, muted: false } };
	const source = { id: 2, isSink: false, audio: { volume: 0.7, muted: true } };
	const other = { id: 3, isSink: false, audio: { volume: 1, muted: false } };
	const playback = { id: 4, isStream: true, ready: true, properties: { "media.class": "Stream/Output/Audio" }, audio: { volume: 0.2, muted: false } };
	const capture = { id: 5, isStream: true, ready: true, properties: { "media.class": "Stream/Input/Audio" }, audio: {} };
	const notReady = { id: 6, isStream: true, ready: false, properties: { "media.class": "Stream/Output/Audio" } };
	const nodes = [sink, source, other, playback, capture, notReady];

	assert(audioDevices(nodes, false).length === 1 && audioDevices(nodes, false)[0] === sink, "output devices are the sinks that have audio");
	assert(audioDevices(nodes, true).length === 2, "input devices are every source that has audio");
	assert(audioDevices(null, false).length === 0, "no nodes, no devices");
	assert(firstDevice(nodes, true) === source, "the first source is the fallback device");
	assert(shownStream(playback) && !shownStream(capture) && !shownStream(notReady) && !shownStream(sink), "only a ready playback stream belongs in the mixer");
	assert(inputStream(capture) && !inputStream(playback) && !inputStream(null), "a capture stream is an input stream");
	assert(streamPlaying(playback, [4]) && !streamPlaying(playback, [9]) && !streamPlaying(null, [4]), "a stream is playing when the poll saw its id");
	assert(streamNodes(nodes, [4], true).length === 1 && streamNodes(nodes, [4], true)[0] === playback, "with the playing filter on only the playing streams stay");
	assert(streamNodes(nodes, [], false).length === 1, "with the filter off every shown stream stays");
	assert(streamVisible(playback, [4], true, {}) && !streamVisible(playback, [9], true, {}), "a stream is on screen while the poll sees it playing");
	assert(streamVisible(playback, [], true, { 4: 5000 }), "a held stream stays on screen while its hold is alive");
	assert(!streamVisible(notReady, [6], false, {}) && !streamVisible(sink, [1], false, {}), "an unbound node and a device never reach the app row");
	assert(anyStreamVisible(nodes, [4], true, {}) && anyStreamVisible(nodes, [], true, { 4: 5000 }), "the app row is drawn from the nodes, not from a width it laid out itself");
	assert(!anyStreamVisible(nodes, [], true, {}) && !anyStreamVisible(null, [4], false, {}), "with nothing playing and nothing held the app row stays away");
	assert(nodeMuted(source) && !nodeMuted(sink) && nodeMuted(null) === false, "mute is read off the node, a missing node reads false");
	assert(nodeVolume(source) === 0.7 && nodeVolume(null) === 0 && nodeVolume(notReady) === 0, "volume is read off the node, a node without audio reads zero");
	assert(sameNode(sink, { id: 1 }) && !sameNode(sink, source) && !sameNode(null, sink), "two nodes are the same node when their ids match");

	const fader = { id: 9, audio: { volume: 0.5, muted: false } };

	assert(setNodeVolume(fader, 0.25, 1) === 0.25 && fader.audio.volume === 0.25, "a fader press sets the node's volume from where it was clicked");
	assert(setNodeVolume(fader, 2, 1) === 1 && fader.audio.volume === 1, "a click past the top of the track clamps to full volume");
	assert(setNodeVolume(fader, -1, 1) === 0 && fader.audio.volume === 0, "a click past the bottom of the track clamps to silence");
	assert(setNodeVolume(fader, 0.5, 1.5) === 0.75 && fader.audio.volume === 0.75, "a click halfway up the track scales to half of the config's maximum volume");
	assert(setNodeVolume({ id: 10 }, 0.5, 1) === 0.5, "a node without audio is left alone instead of thrown on");

	assert(holdStream({}, 4, 5000)[4] === 5000, "holding a stream records when its hold runs out");
	assert(Object.keys(holdStream({ 4: 5000 }, 4, 6000)).length === 1 && holdStream({ 4: 5000 }, 4, 6000)[4] === 6000, "holding the same stream again moves its hold, it does not pile up");
	assert(Object.keys(holdStream({ 4: 5000 }, 5, 6000)).length === 2, "a second stream gets its own deadline");
	assert(JSON.stringify(pruneHolds({ 4: 5000, 5: 6000 }, 5500)) === JSON.stringify({ 5: 6000 }), "a prune drops the holds that ran out and keeps the live ones");
	assert(Object.keys(pruneHolds({ 4: 5000 }, 5000)).length === 0, "a hold is over on its own deadline, not a tick later");
	assert(Object.keys(pruneHolds(undefined, 10)).length === 0, "pruning an empty hold list is safe");

	const sorted = sortedDevices(nodes, true, other);

	assert(sorted[0] === other && sorted.length === 2, "the active device moves to the front of the picker");
	assert(sorted[1] === source, "the rest of the picker keeps its order");
	assert(sortedDevices(nodes, true, source)[0] === source, "a device that is already first is left where it is");
	assert(sortedDevices(nodes, false, null)[0] === sink, "with nothing active the list is left alone");

	const cardDump = function (params) {
		return JSON.stringify([
			{ type: "PipeWire:Interface:Device", id: 46, info: params },
			{ type: "PipeWire:Interface:Node", id: 55, info: { props: { "media.class": "Audio/Source", "device.id": 46 } } }
		]);
	};

	assert(hasMicrophone(cardDump({ params: { EnumRoute: [{ direction: "Input", available: "no" }] } })) === false, "a card whose input jack is empty has no microphone");
	assert(hasMicrophone(cardDump({ params: { EnumRoute: [{ direction: "Input", available: "yes" }] } })) === true, "an available input jack is a microphone");
	assert(hasMicrophone(cardDump({ params: { EnumRoute: [{ direction: "Output", available: "yes" }] } })) === false, "an output jack is not a microphone");
	assert(hasMicrophone(cardDump({ params: { EnumRoute: [{ direction: "Input", available: "no" }, { direction: "Input", available: "yes" }, { direction: "Output", available: "no" }] } })) === true, "one live jack among the dead ones is a microphone");
	assert(hasMicrophone(cardDump({ params: { EnumRoute: [{ direction: "Input", available: "unknown" }] } })) === true, "a card without jack detection keeps its microphone");
	assert(hasMicrophone(cardDump({})) === true, "a card that reports no routes is assumed to have a real microphone");
	assert(hasMicrophone(JSON.stringify([{ type: "PipeWire:Interface:Node", id: 1, info: { props: { "media.class": "Audio/Sink" } } }])) === false, "no source at all means no microphone");
	assert(hasMicrophone("") === true, "an unreadable dump keeps the microphone");
});

section("display", function () {
const mode = parseMode("2560x1440@239.97Hz");

assert(mode.width === 2560 && mode.height === 1440 && mode.refresh === 239.97, "a mode string splits into width, height and refresh");
assert(parseMode("1920x1080").refresh === 0, "a mode with no refresh keeps a zero refresh");
assert(parseMode("nonsense") === null && parseMode("") === null && parseMode(null) === null, "a mode that is not a mode is null");
assert(modeText(mode) === "2560x1440@240", "a mode is written in whole hertz, because hyprland falls back to a safe mode otherwise, got " + modeText(mode));
assert(sameMode(mode, parseMode("2560x1440@240")) === true, "a mode matches the whole hertz the record was written in");
assert(sameMode(mode, parseMode("2560x1440@144")) === false, "and does not match a different refresh");
assert(sameMode(mode, null) === false && sameMode(null, null) === false, "a missing mode matches nothing");
assert(modeText(parseMode("1920x1080")) === "1920x1080", "a refreshless mode prints without an at sign");
assert(modeText(null) === "", "no mode prints as nothing");
assert(modeRank(mode) > modeRank(parseMode("1920x1080@200")), "a bigger panel outranks a faster small one");
assert(scaleLabel(1.6) === "1.6x" && scaleLabel(1) === "1x" && scaleLabel(1.25) === "1.25x", "a scale reads back the way it was set");

const raw = JSON.stringify([
	{ name: "DP-1", width: 2560, height: 1440, refreshRate: 239.97, scale: 1.6, focused: true, availableModes: ["2560x1440@239.97Hz", "2560x1440@144.00Hz", "1920x1080@60.00Hz", "2560x1440@239.97Hz"] },
	{ name: "HDMI-A-1", width: 1920, height: 1080, refreshRate: 60, scale: 1, focused: false, availableModes: [] }
]);
const list = monitorsFromText(raw);

assert(list.length === 2 && list[0].name === "DP-1", "every monitor in the list is kept");
assert(list[0].focused === true && list[1].focused === false, "which monitor holds focus comes through");
assert(list[0].modes.length === 3, "a mode the driver lists twice is offered once");
assert(modeText(list[0].modes[0]) === "2560x1440@240", "the biggest mode leads the list");
assert(list[0].modes[2].width === 1920, "smaller modes follow it");
assert(list[1].modes.length === 1, "the mode a monitor is running is offered even when the driver lists nothing");
assert(monitorsFromText("not json").length === 0 && monitorsFromText("").length === 0, "garbage monitor output is an empty list, not a throw");
assert(findMonitor(list, "HDMI-A-1").name === "HDMI-A-1", "a named monitor is found");
assert(findMonitor(list, "").name === "DP-1" && findMonitor(list, null).name === "DP-1", "with no name the focused monitor is picked");
assert(findMonitor(list, "nope").name === "DP-1", "an unknown name falls back to the focused monitor");
assert(findMonitor([], "") === null && findMonitor(null, "") === null, "no monitors is null, not a throw");
assert(refreshLabel(list[0]) === "240 Hz", "the header reads the refresh");
assert(resolutionsOf(list[0]).length === 2, "resolutions are the modes without the refresh");
assert(refreshesFor(list[0], { width: 2560, height: 1440 }).length === 2, "one resolution keeps only its own refreshes");
assert(refreshesFor(list[0], null).length === 0, "no resolution has no refreshes");

const state = detect(raw, 12, 10);

assert(state.outputs["DP-1"].mode === "2560x1440@240", "detection takes the best mode of each monitor");
assert(state.outputs["HDMI-A-1"].scale === 1, "detection keeps the scale a monitor is running");
assert(state.fallback.mode === "2560x1440@240", "the fallback is the first monitor's best mode");
assert(detect("", 12, 10).fallback.scale === 1, "detecting nothing still leaves a usable fallback");

const text = renderLua(state);
const back = stateFromText(text);

assert(back.fontSize === 12 && back.iconSize === 10, "the record keeps the font sizes");
assert(back.outputs["DP-1"].mode === "2560x1440@240" && back.outputs["DP-1"].scale === 1.6, "a rendered record parses back to what went in");
assert(back.fallback.mode === state.fallback.mode && back.fallback.scale === state.fallback.scale, "the fallback rides along too");
assert(renderLua(back) === text, "and renders byte for byte the same record again");
assert(Object.keys(stateFromText("").outputs).length === 0, "a missing record is empty, not a throw");
assert(stateFromText("return {\n\tfontSize = 14,\n}").fontSize === 14, "a record written by hand still reads");

const cleanScales = scaleSteps(list[0], 1, 2);

assert(cleanScales.length === 7, "2560x1440 has seven clean scales between one and two, got " + cleanScales.length);
assert(cleanScales.indexOf(1.6) >= 0 && cleanScales.indexOf(1.25) >= 0 && cleanScales.indexOf(2) >= 0, "the scales the panel offers are the ones hyprland keeps");
assert(cleanScales.indexOf(1.5) < 0 && cleanScales.indexOf(1.75) < 0, "1.5 and 1.75 do not divide 2560x1440, so they are never offered");
assert(cleanScale(list[0], 1.75) === 200 / 120, "asking for 1.75 lands on the nearest clean scale, 1.6667, got " + cleanScale(list[0], 1.75));
assert(cleanScale(list[0], 1.52) === 1.6, "a scale between two clean ones rounds to the nearer, got " + cleanScale(list[0], 1.52));
assert(cleanScale(list[0], 1.6) === 1.6, "a scale that is already clean stays put");
assert(scaleSteps(list[1], 1, 2).indexOf(1.5) >= 0, "1.5 is clean on 1920x1080, the rule follows the resolution");
assert(scaleSteps(null, 1, 2).length === 0 && cleanScale(null, 2) === 2, "a monitor that is not there offers nothing and changes nothing");
assert(sameScale(1.6666666, 200 / 120) === true, "a scale hyprland rounded in its own output still matches the clean one");
assert(sameScale(1.6, 1.75) === false, "and two different scales do not match");
assert(numberText(1.6666666) === "1.666667" && trimNumber(1.6666666) === "1.67", "the record keeps more digits than the label so a clean scale survives being written back");

const scaled = setOutput(state, "DP-1", { scale: 1.5 });

assert(scaled.outputs["DP-1"].scale === 1.5, "a scale change lands on the named monitor");
assert(state.outputs["DP-1"].scale === 1.6, "and leaves the state it came from alone");
assert(scaled.outputs["DP-1"].mode === "2560x1440@240" && scaled.outputs["HDMI-A-1"].mode === "1920x1080@60", "the modes of the other monitors ride along");
assert(Object.keys(scaled.outputs).length === 2, "a change does not add a monitor");

const fresh = setOutput(state, "eDP-1", { mode: "1280x720@60" });

assert(fresh.outputs["eDP-1"].mode === "1280x720@60" && fresh.outputs["eDP-1"].scale === 1, "a monitor not yet in the record starts from its own defaults");

const bigger = setFontSize(state, 18);

assert(bigger.fontSize === 18 && bigger.iconSize === 15, "the icon grows with the font at the ratio already set, got " + bigger.iconSize);
assert(setFontSize(state, 8).iconSize === 7, "a smaller font shrinks the icon by the same ratio");
assert(setFontSize({ fontSize: 0, iconSize: 0, outputs: {} }, 12).iconSize === 10, "a record with no ratio falls back to the design one");
assert(state.fontSize === 12, "resizing leaves the state it came from alone");

const rows = rowNames();

assert(rows.join() === "scale,refresh,font,resolution", "the panel walks the bars and then the resolution list");
assert(moveCursor(rows, 6, 0, 3, 1).row === 1, "down from the first bar reaches the second");
assert(moveCursor(rows, 6, 2, 3, 1).row === 3 && moveCursor(rows, 6, 2, 3, 1).step === 0, "down from the last bar lands on the first resolution");
assert(moveCursor(rows, 6, 3, 0, 1).step === 1 && moveCursor(rows, 6, 3, 1, 1).step === 2, "down keeps walking the resolutions instead of jumping away");
assert(moveCursor(rows, 6, 3, 5, 1).row === 0, "down past the last resolution starts the panel over at the first bar");
assert(moveCursor(rows, 6, 3, 0, -1).row === 2 && moveCursor(rows, 6, 3, 0, -1).step === -1, "up from the first resolution returns to the bar it came from");
assert(moveCursor(rows, 6, 0, 0, -1).row === 3 && moveCursor(rows, 6, 0, 0, -1).step === 5, "up from the first bar wraps to the last resolution");
assert(moveCursor(rows, 0, 2, 3, 1).row === 0, "a monitor with no resolutions walks the bars only");
assert(moveCursor(rows, 0, 0, 0, -1).row === 2, "and wraps between them when it has nothing between");
assert(moveCursor(rows, -1, 1, 0, 1).row === 2, "a broken count does not walk off the end");
assert(moveCursor([], 4, 0, 0, 1).row === 0, "a panel with no rows stays put");
});

section("power", function () {
assert(parseBattery("") === null, "an empty uevent has no battery");
assert(parseBattery("POWER_SUPPLY_PRESENT=1\nPOWER_SUPPLY_STATUS=Discharging\nPOWER_SUPPLY_CAPACITY=42\n") !== null, "a normal battery is found");
assert(parseBattery("POWER_SUPPLY_PRESENT=1\nPOWER_SUPPLY_STATUS=Discharging\nPOWER_SUPPLY_CAPACITY=88\n").pct === 88, "the capacity reads as a percent");
assert(parseBattery("POWER_SUPPLY_PRESENT=0\nPOWER_SUPPLY_CAPACITY=50\n") === null, "an absent battery reads as none");
assert(parseBattery("POWER_SUPPLY_PRESENT=1\nPOWER_SUPPLY_STATUS=Charging\nPOWER_SUPPLY_CAPACITY=10\n").charging === true, "a charging battery is marked");
assert(parseBattery("POWER_SUPPLY_PRESENT=1\nPOWER_SUPPLY_STATUS=Full\nPOWER_SUPPLY_CAPACITY=100\n").charging === true, "a full battery counts as charging");
assert(parseBattery("POWER_SUPPLY_PRESENT=1\nPOWER_SUPPLY_STATUS=Not charging\nPOWER_SUPPLY_CAPACITY=60\n").charging === false, "not charging is not charging");
assert(parseBattery("POWER_SUPPLY_CAPACITY=50\n") !== null, "a battery without a present flag still shows");

const icons = { full: "F", high: "H", mid: "M", low: "L", alert: "A", charge: "C", plug: "P" };
assert(batteryIcon(null, icons) === "P", "no battery shows the plug");
assert(batteryIcon({ pct: 100, charging: false }, icons) === "F", "a battery at a hundred shows full");
assert(batteryIcon({ pct: 90, charging: false }, icons) === "F", "ninety and up shows full");
assert(batteryIcon({ pct: 89, charging: false }, icons) === "H", "eighty nine shows high");
assert(batteryIcon({ pct: 60, charging: false }, icons) === "H", "sixty shows high");
assert(batteryIcon({ pct: 59, charging: false }, icons) === "M", "fifty nine shows mid");
assert(batteryIcon({ pct: 30, charging: false }, icons) === "M", "thirty shows mid");
assert(batteryIcon({ pct: 29, charging: false }, icons) === "L", "twenty nine shows low");
assert(batteryIcon({ pct: 10, charging: false }, icons) === "L", "ten shows low");
assert(batteryIcon({ pct: 9, charging: false }, icons) === "A", "nine shows the warning");
assert(batteryIcon({ pct: 50, charging: true }, icons) === "C", "charging overrides the level");

assert(cpuGovernors("performance powersave\n").length === 2, "the governors list comes through");
assert(cpuGovernors("performance powersave\n")[0] === "performance", "and in order");
assert(cpuGovernors("") .length === 0, "no cpufreq, no governors");
assert(cpuGovernors("[wiggle] performance\n").length === 2, "a bracketed governor is unbracketed");
assert(cpuGovernors("other: info\n\nperformance powersave\n").length === 2, "the governor line is found among other lines");
assert(currentGovernor("scaling_governor: performance powersave\n") === "", "without a bracket nothing is current");
assert(currentGovernor("scaling_governor: [performance] powersave\n") === "performance", "the bracketed governor is the current one");
assert(currentGovernor("other: info\nscaling_governor: [powersave] performance\n") === "powersave", "the current one is found among other lines");
assert(governorCommand("performance").join(" ").indexOf("performance") >= 0, "the governor command carries the governor");
assert(governorCommand("powersave")[2].indexOf("cpu*") > 0, "the command reaches every cpu");
});

section("network", function () {
const devs = parseDevs("enp4s0:ethernet:connected:Wired connection 1\nlo:loopback:connected (externally):lo\nwlp5s0:wifi:disconnected:(none)\n");

assert(devs.length === 3, "every device line becomes a row");
assert(devs[0].device === "enp4s0" && devs[0].type === "ethernet", "a wired card reads as ethernet");
assert(devs[2].state === "disconnected" && devs[2].connection === "(none)", "an unplugged card knows it is not connected");
assert(pickDev(devs).device === "enp4s0", "the wired card is picked");
assert(pickDev(parseDevs("wlp5s0:wifi:connected:Casa\n")).type === "wifi", "on wifi alone the wireless card is picked");
assert(pickDev(parseDevs("lo:loopback:connected:lo\n")) === null, "a loopback only box has nothing to show");
assert(parseDevs("").length === 0 && parseDevs(null).length === 0, "no devices at all is not a crash");
assert(parseDevs("garbage").length === 0, "a malformed line is dropped rather than thrown");

const rates = parseRates("Inter-|   Receive\n face |bytes packets\n    lo: 100 5 0 0 0 0 0 0 100 5\nenp4s0: 4096 9 0 0 0 0 0 0 2048 9\n");

assert(rates.lo.rx === 100 && rates.lo.tx === 100, "loopback is parsed even though it is filtered later");
assert(rates.enp4s0.rx === 4096 && rates.enp4s0.tx === 2048, "receive and transmit bytes land in the right slots");
assert(parseRates("").enp4s0 === undefined, "an empty reading gives no devices");

assert(deviceInfo("IP4.ADDRESS[1]:10.0.0.184/24\nIP4.GATEWAY:10.0.0.1\nIP4.DNS[1]:75.75.75.75\nIP4.DNS[2]:75.75.76.76\n").ip === "10.0.0.184/24", "the address comes through with its mask");
assert(deviceInfo("IP4.ADDRESS[1]:10.0.0.184/24\nIP4.GATEWAY:10.0.0.1\nIP4.DNS[1]:75.75.75.75\nIP4.DNS[2]:75.75.76.76\n").gateway === "10.0.0.1", "the gateway comes through");
assert(deviceInfo("IP4.ADDRESS[1]:10.0.0.184/24\nIP4.GATEWAY:10.0.0.1\nIP4.DNS[1]:75.75.75.75\nIP4.DNS[2]:75.75.76.76\n").dns === "75.75.75.75", "only the first dns server is listed");
assert(deviceInfo("GENERAL.DEVICE:enp4s0\n").ip === "" && deviceInfo("").gateway === "", "a link with no ipv4 yet reads as blank instead of undefined");

const before = { enp4s0: { rx: 1000, tx: 500 } };
const after = { enp4s0: { rx: 3000, tx: 1500 } };
const moved = rateBetween(before, after, "enp4s0", 2);

assert(moved.down === 1000 && moved.up === 500, "byte counters become a rate over the elapsed seconds");
assert(rateBetween(before, after, "wlp5s0", 2).down === 0, "a device that was not counted before reads as idle");
assert(rateBetween(before, after, "enp4s0", 0).down === 0, "no elapsed time does not divide by zero");
assert(rateBetween({ enp4s0: { rx: 9000, tx: 9000 } }, after, "enp4s0", 2).down === 0, "a counter that went backwards is clamped instead of going negative");

assert(rateText(512) === "512 B/s", "tiny transfers stay in bytes");
assert(rateText(2048) === "2 KB/s", "kilobytes drop the decimal");
assert(rateText(1024 * 1024 * 3.5) === "3.5 MB/s", "megabytes keep one decimal");
assert(rateText(0) === "0 B/s" && rateText(null) === "0 B/s", "nothing moving reads as zero");
assert(megaText(1024 * 1024 * 12.34) === "12.3", "the speed test result reads as plain megabytes");

assert(signalBars(100) === 4 && signalBars(81) === 4, "above eighty is a full four bars");
assert(signalBars(80) === 3 && signalBars(56) === 3, "eighty and under drops to three bars");
assert(signalBars(55) === 2 && signalBars(31) === 2, "fifty five and under keeps two bars");
assert(signalBars(30) === 1 && signalBars(6) === 1, "anything above five still gets one bar");
assert(signalBars(5) === 0 && signalBars(0) === 0 && signalBars(null) === 0, "five and under shows no bars at all");

const wifi = parseWifiList("*:Casa:88:6:2437 MHz:WPA2:AA\\:BB\\:CC\\:DD\\:EE\\:FF\n:My Phone:72:1:2412 MHz:WPA2 WPA3:11\\:22\\:33\\:44\\:55\\:66\n::90:11:5180 MHz::00\\:11\\:22\\:33\\:44\\:55\n");

assert(wifi.length === 3, "every network with a row is kept");
assert(wifi[0].active === true && wifi[1].active === false, "the connected network is marked, the rest are not");
assert(wifi[0].ssid === "Casa" && wifi[0].signal === 88, "ssid and signal come through");
assert(wifi[0].bssid === "AA:BB:CC:DD:EE:FF", "escaped colons in a mac address are unescaped");
assert(wifi[2].ssid === "", "a hidden network keeps its row with an empty ssid");
assert(wifi[1].security === "WPA2 WPA3", "a space in the security field survives");
assert(wifi[0].freq === "2437 MHz", "the frequency column comes through");
assert(parseWifiList("").length === 0 && parseWifiList(null).length === 0, "no networks is an empty list");
assert(parseWifiList("short").length === 0, "a truncated line is dropped");

assert(currentSignal("*:Casa:88:6:2437 MHz:WPA2:AA\\:BB\n:Other:40:1:2412 MHz:WPA2:CC\\:DD\n") === 88, "the connected network's signal is read from the scan");
assert(currentSignal(":Other:40:1:2412 MHz:WPA2:CC\\:DD\n") === -1, "with nothing connected the signal reads as unknown");

const known = knownNetworks("Casa:aaa-bbb\nGuest:ccc-ddd\n\n");

assert(known.length === 2 && known[0].name === "Casa" && known[0].uuid === "aaa-bbb", "saved profiles come back as name and uuid");
assert(knownNetworks("").length === 0, "no saved profiles is an empty list");

assert(connectCommand("Casa", "hunter2", false).join(" ") === "nmcli dev wifi connect Casa password hunter2", "a secured network takes its password");
assert(connectCommand("Cafe", "", false).join(" ") === "nmcli dev wifi connect Cafe", "an open network needs no password");
assert(connectCommand("Hidden", "", true).join(" ") === "nmcli dev wifi connect Hidden hidden yes", "a hidden network is told it is hidden");
assert(forgetCommand("Casa").join(" ") === "nmcli connection delete id Casa", "forgetting removes the saved profile");
assert(disconnectCommand("wlp5s0").join(" ") === "nmcli device disconnect wlp5s0", "disconnecting drops the link");
assert(radioCommand(false).join(" ") === "nmcli radio wifi off", "the radio can be turned off");
assert(radioCommand(true).join(" ") === "nmcli radio wifi on", "the radio can be turned back on");
assert(listCommand().join(" ") === "nmcli -t -f IN-USE,SSID,SIGNAL,CHAN,FREQ,SECURITY,BSSID device wifi list", "the scan asks for exactly the columns that are drawn");
assert(scanCommand("wlp5s0").join(" ") === "nmcli --wait 10 device wifi rescan ifname wlp5s0", "a rescan waits for the hardware instead of racing it");

const down = speedDownCommand("https://speed.cloudflare.com/__down", 1000000);

assert(down[down.length - 1].indexOf("__down?bytes=1000000") >= 0, "the download test asks for a known size");
assert(down[down.length - 1].indexOf("speed_download") < 0, "the transfer is silent so the sampling loop owns the reading");
assert(Config.networkSpeedBytes < 100000000, "the download stays under the size the server refuses with a 403");

const up = speedUpCommand("https://speed.cloudflare.com/__up", 500);

assert(up[0] === "sh" && up[2].indexOf("speed_upload") < 0, "the upload test is a quiet shell pipe the sampling loop can watch");

assert(megaBits(125000).toFixed(1) === "1.0", "a byte rate converts to megabits per second");
assert(Config.notifyWidth === Math.round(280 * Config.notifyScale), "the notification width follows the size");
assert(Config.notifySlot === Math.round(26 * Config.notifyScale), "the notification icon follows the size");
assert(Config.notifyRowHeight === Math.round(38 * Config.notifyScale), "the notification row follows the size");
assert(Config.notifyAppFontSize === Math.round(11 * Config.notifyScale), "the notification text follows the size");
assert(megaBits(0) === 0 && megaBits(null) === 0, "no traffic reads as zero megabits");
assert(speedText(125000) === "1", "a megabit reads as a whole number");
assert(speedText(12500000) === "100", "triple digit speeds stay whole numbers");
assert(speedText(null) === "0", "a missing reading is not a crash");

assert(speedCeiling(0) === 625000, "a needle with nothing to show rests on the first rung");
assert(speedCeiling(125000) === 625000, "one megabit sits inside the five megabit rung");
assert(speedCeiling(12500000) === 31250000, "a speed on a rung still gets headroom above it");
assert(speedCeiling(15000000) === 31250000, "a speed past its rung climbs to the next one");
assert(speedCeiling(null) === 625000, "a missing reading is a floor, not a crash");
assert(speedCeiling(62375000) === 125000000, "499 megabits reads half dial, not pegged");
assert(speedCeiling(100000000) === 125000000, "800 megabits keeps climbing on the same dial");
assert(speedCeiling(118750000) === 125000000, "950 megabits reaches the end of the dial");
assert(speedCeiling(1e12) === 125000000, "absurd speeds stop at the top rung");

assert(brailleGraph([], 1, 3, "down").length === 3, "an empty graph still draws its full width");
assert(brailleGraph([0], 0, 1, "down").codePointAt(0) === 0x2800, "no traffic is a blank cell");
assert(brailleGraph([100000, 100000], 100000, 1, "down").codePointAt(0) === 0x28ff, "a full bar lights every dot");
assert(brailleGraph([50000, 50000], 100000, 1, "down").codePointAt(0) === 0x28cc, "download bars fill from the floor");
assert(brailleGraph([50000, 50000], 100000, 1, "up").codePointAt(0) === 0x2833, "upload bars fill from the ceiling");
assert(brailleGraph([20000, 20000], 100000, 1, "down").codePointAt(0) === 0x2888, "a whisper over the noise floor still lights a dot");
assert(brailleGraph([100000, 100], 100000, 1, "down").codePointAt(0) === 0x280f, "a stray byte next to the peak stays dark");
assert(brailleGraph([10000, 10000], 100000, 1, "down").codePointAt(0) === 0x2800, "ten kilobytes stay dark under the noise floor");
assert(brailleGraph([100000], 100000, 3, "down") === "⠀⠀⣰", "a fresh reading hugs the right edge");
assert(brailleGraph([100000, 0], 100000, 1, "down").codePointAt(0) === 0x280f, "two samples share one cell left to right");
assert(brailleGraph([0, 0, 100000], 100000, 3, "down") === "⠀⠀⣰", "young traffic hugs the right edge");
assert(brailleGraph([100, 200, 50000], 50000, 3, "down") === "⠀⠀⣰", "a burst after trickle still lands on the right edge");
assert(brailleGraph([0, 0, 0], 100, 2, "down").length === 2, "an idle line stays blank but full width");
assert(brailleGraph([0, 100000, 0, 0, 0, 50000], 100000, 6, "down") === "⠀⠀⠀⣰⠀⣀", "gappy traffic keeps its shape while young");
assert(brailleGraph([0, 0, 20000, 40000, 60000, 80000, 100000, 120000], 120000, 3, "down") === "⢈⣬⣾", "once the window fills the newest samples scroll one to one");
assert(brailleMasks([100000, 100000], 100000, 1, "down")[0] === 0xff, "a full cell lights all eight dots");
assert(brailleMasks([0, 100000, 0, 0, 0, 50000], 100000, 6, "up").length === 6, "masks come back one per cell");
});

console.log("check ok (" + ran + " assertions)");
