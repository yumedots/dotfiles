const fs = require("fs");

eval(fs.readFileSync(__dirname + "/helpers.js", "utf8").replace(".pragma library", ""));

function assert(condition, message) {
	if (!condition)
		throw new Error(message);
}

const Config = new Function(fs.readFileSync(__dirname + "/../config.js", "utf8").replace(".pragma library", "")
	+ "\nreturn { weatherCodes: weatherCodes, weatherCoords: weatherCoords, weatherIcon: weatherIcon, weatherLoadingIcon: weatherLoadingIcon, weatherLocation: weatherLocation, weatherStationCount: weatherStationCount };")();

const entries = parseDesktopEntries([
	"/usr/share/applications/foot.desktop:Name=Foot",
	"/usr/share/applications/foot.desktop:Exec=foot --server",
	"/usr/share/applications/foot.desktop:Icon=foot",
	"/usr/share/applications/code-insiders.desktop:Name=Visual Studio Code - Insiders",
	"/usr/share/applications/code-insiders.desktop:Exec=code-insiders %F",
	"/usr/share/applications/code-insiders.desktop:Icon=vscode-insiders",
	"/usr/share/applications/code-insiders.desktop:StartupWMClass=Code - Insiders",
	"/usr/share/applications/code-insiders.desktop:Name=New Empty Window",
	"/usr/share/applications/code-insiders.desktop:Icon=wrong-icon",
	"/usr/share/applications/firefox.desktop:Name=Firefox",
	"/usr/share/applications/firefox.desktop:Exec=/usr/lib/firefox/firefox %u",
	"/usr/share/applications/firefox.desktop:Icon=firefox",
	"/usr/share/applications/foo.desktop:Name=Foo Bar",
	"/usr/share/applications/foo.desktop:Icon=foo",
	"/usr/share/applications/foo.desktop:Terminal=true",
	"/usr/share/applications/hidden.desktop:Name=Hidden App",
	"/usr/share/applications/hidden.desktop:Icon=hidden",
	"/usr/share/applications/hidden.desktop:NoDisplay=true"
].join("\n"));

assert(lookupApp(entries, "firefox").icon === "firefox", "id lookup");
assert(lookupApp(entries, "firefox").exec === "firefox", "exec basename comes from the first token only");
assert(lookupApp(entries, "Code - Insiders").id === "code-insiders", "wmclass lookup");
assert(lookupApp(entries, "code-insiders").icon === "vscode-insiders", "action groups do not overwrite the main icon");
assert(lookupApp(entries, "foo bar").id === "foo", "display name lookup");
assert(lookupApp(entries, "foo").terminal === true, "Terminal=true is parsed");
assert(lookupApp(entries, "hidden") === null, "NoDisplay entries are skipped");
assert(lookupApp(entries, "nope") === null, "unknown ids return null");
assert(lookupApp(entries, "") === null, "empty names return null");
assert(daysInMonth(2024, 1) === 29 && daysInMonth(2026, 1) === 28, "february length");
assert(weekdayOffset(new Date(2024, 0, 1), 1) === 0, "2024-01-01 is a monday");
assert(weekdayOffset(new Date(2026, 8, 1), 1) === 1, "2026-09-01 is a tuesday in a monday week");
assert(weekdayOffset(new Date(2026, 8, 1), 0) === 2, "and a tuesday two cells into a sunday week");
assert(weekdayOffset(new Date(2026, 8, 1), 9) === weekdayOffset(new Date(2026, 8, 1), 1), "a week start off the calendar falls back to monday");
assert(weekdayLabels(1)[0] === "Mon" && weekdayLabels(1)[6] === "Sun", "a monday week runs mon to sun");
assert(weekdayLabels(0)[0] === "Sun" && weekdayLabels(0)[6] === "Sat", "a sunday week runs sun to sat");
assert(dateKey(new Date(2026, 8, 5)) === "2026-09-05", "keys pad the month and the day");
const mondayGrid = monthGrid(2026, 8, 1, "2026-09-15", "2026-09-01", 6);
assert(mondayGrid.length === 6, "a monday week month is six rows");
assert(mondayGrid[0][0].key === "2026-08-31" && mondayGrid[0][0].inMonth === false, "a month starting mid week leads with the previous month");
assert(mondayGrid[0][1].key === "2026-09-01" && mondayGrid[0][1].cursor === true, "the cursor lands on its own cell");
assert(mondayGrid[2][1].key === "2026-09-15" && mondayGrid[2][1].today === true, "today lands on its own cell");
assert(mondayGrid[2][1].cursor === false, "and is not the cursor");
assert(mondayGrid[0][3].weekend === false && mondayGrid[0][5].weekend === true, "weekends are marked");
assert(mondayGrid.every(function (row) { return row.length === 7; }), "every row holds seven days");

const sundayGrid = monthGrid(2026, 8, 0, "", "", 6);
assert(sundayGrid[0][0].key === "2026-08-30", "a sunday week leads one day earlier");
assert(sundayGrid[0][2].key === "2026-09-01", "and still lands on the first of the month");
assert(monthGrid(2026, 1, 1, "", "", 6).length === 6, "february is six rows tall too");

const midnight = new Date(2026, 8, 15, 0, 0, 0);
const noon = new Date(2026, 8, 15, 12, 0, 0);
assert(dayProgress(noon) === 0.5, "noon is half the day gone");
assert(progressPercent(dayProgress(midnight)) === 0 && progressPercent(dayProgress(new Date(2026, 8, 15, 23, 59))) === 100, "a day runs 0 to 100");
assert(progressPercent(monthProgress(midnight)) === 47, "the 15th of a 30 day month is 47 percent done");
assert(progressPercent(monthProgress(new Date(2026, 8, 30))) === 97, "the last day of the month is not quite over");
assert(progressPercent(yearProgress(midnight)) === 70, "september 15 is 70 percent of the year");
assert(progressPercent(yearProgress(new Date(2026, 0, 1))) === 0 && progressPercent(yearProgress(new Date(2026, 11, 31, 12))) === 100, "a year runs 0 to 100");
assert(progressPercent(yearProgress(new Date(2024, 11, 31, 12))) === 100, "a leap year is 366 days long");
assert(lifeProgress(1980, 90, 2026) === 46 / 90, "life runs from the birth year");
assert(progressPercent(lifeProgress(1980, 90, 2026)) === 51, "and reports a percent");
assert(lifeProgress(0, 90, 2026) === 0 && lifeProgress(2030, 90, 2026) === 0, "an unset or future birth year leaves the meter empty");

const lastDay = new Date(2026, 8, 30);
assert(shiftDays(lastDay, 1).getMonth() === 9 && shiftDays(lastDay, 1).getDate() === 1, "a day forward crosses into the next month");
assert(shiftDays(new Date(2026, 0, 1), -1).getMonth() === 11 && shiftDays(new Date(2026, 0, 1), -1).getDate() === 31, "a day back crosses into the previous december");
assert(shiftDays(new Date(2026, 8, 30), 7).getMonth() === 9 && shiftDays(new Date(2026, 8, 30), 7).getDate() === 7, "a week forward keeps the weekday");
assert(shiftDays(new Date(2026, 8, 15), -7).getDate() === 8, "a week back keeps the weekday");
assert(shiftMonths(new Date(2026, 0, 31), 1).getDate() === 28, "a month forward clamps the 31st to a shorter month");
assert(shiftMonths(new Date(2026, 11, 15), 1).getFullYear() === 2027 && shiftMonths(new Date(2026, 11, 15), 1).getMonth() === 0, "a month forward crosses into the next year");
assert(shiftMonths(new Date(2026, 0, 15), -1).getFullYear() === 2025, "a month back crosses into the previous year");
assert(shiftYears(new Date(2024, 1, 29), 1).getDate() === 28, "a year forward clamps the 29th of february");
assert(shiftDays(lastDay, 0).getDate() === 30, "shifting by nothing leaves the day alone");

let tallest = 0;

for (let year = 2020; year <= 2030; year++) {
	for (let month = 0; month < 12; month++)
		tallest = Math.max(tallest, Math.ceil((weekdayOffset(new Date(year, month, 1), 1) + daysInMonth(year, month)) / 7));
}

assert(tallest === 6, "every month of the decade fits six weeks, so the grid never needs more");
assert(filledCells(50, 15) === 8 && filledCells(200, 15) === 15, "filled cells clamp");

const border = parseHyprBorder([
	'{"option": "general:col.active_border", "gradient": "ee33ccff ee00ff99 45deg", "set": true }',
	'{"option": "general:border_size", "int": 1, "set": true }'
].join("\n"));

assert(border.colors[0] === "#ee33ccff" && border.colors[1] === "#ee00ff99", "gradient colors keep hyprland's alpha first order");
assert(border.angle === 45, "gradient angle is read");
assert(border.width === 1, "border size is read");

const solidBorder = parseHyprBorder('{"option": "general:col.inactive_border", "gradient": "aa595959 0deg", "set": true }');
assert(solidBorder.colors.length === 1 && solidBorder.colors[0] === "#aa595959", "a single color border is not treated as a gradient");

const unsetBorder = parseHyprBorder('{"option": "general:col.active_border", "gradient": "", "set": false }\n{"option": "general:border_size", "int": 3, "set": true }');
assert(unsetBorder.colors === null && unsetBorder.width === 3, "an unset gradient still reports the border size");

const brokenBorder = parseHyprBorder("hyprctl: command not found\n\n");
assert(brokenBorder.colors === null && brokenBorder.width === null && brokenBorder.angle === 0, "unreadable output leaves the tooltip on its fallback border");

assert(mixColors("#000000", "#ffffff", 0.5) === "#ff808080", "colours mix at the midpoint");
assert(mixColors("#e0000000", "#e0ffffff", 1) === "#e0ffffff", "mixing keeps the alpha channel");
assert(mixColors("#33ccff", "#00ff99", 0) === "#ff33ccff", "a six digit colour is treated as opaque");
assert(mixColors("nonsense", "#ffffff", 0.5) === "nonsense", "an unparsable colour is passed through");
assert(gradientSample(["#000000"], 0.5) === "#000000", "a single colour border stays that colour");
assert(gradientSample(null, 0.5) === null, "no colours, no sample");

const topEdge = gradientEdgeColors(["#000000", "#ffffff"], 0, 100, 40, "top");
assert(topEdge.horizontal === true, "the top edge runs horizontally");
assert(topEdge.start === "#ff2b2b2b" && topEdge.end === "#ffd5d5d5", "the top edge samples the same span the rotated rectangle used");

const flatEdge = gradientEdgeColors(["#000000", "#ffffff"], 90, 100, 40, "top");
assert(flatEdge.start === flatEdge.end, "a 90 degree gradient is flat along the top edge");
const leftEdge = gradientEdgeColors(["#000000", "#ffffff"], 90, 100, 40, "left");
assert(leftEdge.horizontal === false, "the left edge runs vertically");
assert(leftEdge.start === "#ff5e5e5e" && leftEdge.end === "#ffa2a2a2", "a 90 degree gradient runs down the left edge");

const ring = gradientEdges(["#000000", "#ffffff"], 0, 100, 40, 2);
assert(ring.length === 4, "the border is four edges");
assert(ring[0].x === 0 && ring[0].y === 0 && ring[0].width === 100 && ring[0].height === 2, "the top edge sits on the top");
assert(ring[1].y === 38 && ring[1].height === 2, "the bottom edge sits on the bottom");
assert(ring[2].x === 0 && ring[2].y === 2 && ring[2].width === 2 && ring[2].height === 36, "the left edge does not cover the corners");
assert(ring[3].x === 98 && ring[3].width === 2, "the right edge sits on the right");
assert(gradientEdges(["#ffffff"], 0, 10, 10, 0)[0].height === 0, "a zero width border draws nothing");

const gaps = parseHyprGaps([
	'{"option": "general:col.active_border", "gradient": "ee33ccff ee00ff99 45deg", "set": true }',
	'{"option": "general:border_size", "int": 1, "set": true }',
	'{"option": "general:gaps_in", "css": "8 8 8 8", "set": true }',
	'{"option": "general:gaps_out", "css": "15 15 15 15", "set": true }'
].join("\n"));

assert(gaps.inner === 8 && gaps.outer === 15, "gaps come from hyprland's css shorthand, first value");
assert(parseHyprGaps('{"option": "general:gaps_workspaces", "int": 2, "set": true }').inner === null, "gaps_workspaces is not mistaken for gaps_in");
assert(parseHyprGaps("hyprctl: command not found").outer === null, "unreadable output leaves the gaps on their fallback");

const namedColor = parseGradient("rgba(ff0000ff) 90deg");
assert(namedColor.angle === 90 && namedColor.colors === null, "a token that is not a plain hex color is dropped");

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
assert(cleanExec("code-insiders %F") === "code-insiders", "field codes are stripped");
assert(cleanExec("env GDK_BACKEND=x11 firefox %u") === "env GDK_BACKEND=x11 firefox", "an env wrapper stays, only the field code goes");
assert(cleanExec("app 100%%") === "app 100%", "an escaped percent survives");
assert(cleanExec(null) === "", "a missing exec line is empty");
assert(parseDesktopEntries("/a/x.desktop:Exec=/usr/bin/foo --bar %F").x.execLine === "/usr/bin/foo --bar", "the exec line is parsed with the field codes removed");
assert(togglePin([], "yazi")[0] === "yazi", "pin adds to an empty list");
assert(togglePin(["a", "b"], "c").length === 3, "pin keeps the rest");
assert(togglePin(["a", "b"], "b").length === 1, "pin removes what is pinned");
assert(togglePin(["a", "b"], "B").length === 1, "pin removal is case-insensitive");
assert(pinnedFromText("yazi\nbtop\n\n")[0] === "yazi" && pinnedFromText("yazi\nbtop\n\n").length === 2, "pin file lines are trimmed and blanks dropped");
assert(pinnedFromText("").length === 0, "a missing pin file yields nothing");
assert(shellQuote("a b") === "'a b'", "shell quoting wraps spaces");

assert(isOutputStream(true, "Stream/Output/Audio"), "a playback stream counts as a playing app");
assert(!isOutputStream(true, "Stream/Input/Audio"), "a capture stream is not a playing app");
assert(!isOutputStream(false, "Audio/Sink"), "a sink is not an app stream");
assert(isOutputStream(true, ""), "a stream without a media class is still an app stream");
assert(isOutputStream(true, null), "a null media class is still an app stream");
assert(isInputStream(true, "Stream/Input/Audio"), "a capture stream counts as an input stream");
assert(!isInputStream(true, "Stream/Output/Audio"), "a playback stream is not an input stream");
assert(!isInputStream(false, "Audio/Source"), "a source device is not an input stream");
assert(!isInputStream(true, null), "a null media class is not an input stream");

const streamProps = {
	"application.name": "Firefox",
	"application.icon-name": "firefox",
	"application.process.binary": "/usr/lib/firefox/firefox"
};
assert(streamApp(streamProps).name === "Firefox", "the app name comes from the stream properties");
assert(streamApp(streamProps).icons[0] === "firefox", "the app icon name is preferred");
assert(streamApp({ "node.description": "Dummy Output" }).name === "Dummy Output", "a stream without an app name falls back to its description");
assert(streamApp({ "application.process.binary": "/usr/bin/mpv" }).icons.indexOf("mpv") >= 0, "the icon falls back to the process binary");
assert(streamApp(null).name === "" && streamApp(null).icons.length === 0, "missing properties yield nothing");

const nodeDump = JSON.stringify([
	{ id: 53, type: "PipeWire:Interface:Node", info: { state: "running", props: { "media.class": "Audio/Sink" } } },
	{ id: 69, type: "PipeWire:Interface:Node", info: { state: "running", props: { "media.class": "Stream/Output/Audio" } } },
	{ id: 70, type: "PipeWire:Interface:Node", info: { state: "suspended", props: { "media.class": "Stream/Output/Audio" } } },
	{ id: 71, type: "PipeWire:Interface:Node", info: { state: "running", props: { "media.class": "Stream/Input/Audio" } } },
	{ id: 72, type: "PipeWire:Interface:Link", info: { state: "running", props: {} } }
]);

assert(parseRunningStreams(nodeDump).length === 1 && parseRunningStreams(nodeDump)[0] === 69, "only a running playback stream counts as playing");
assert(parseRunningStreams(nodeDump, "output").length === 1, "the default direction is playback");
assert(parseRunningStreams(nodeDump, "input").length === 1 && parseRunningStreams(nodeDump, "input")[0] === 71, "only a running capture stream counts as recording");
assert(parseRunningStreams("not json").length === 0, "a broken dump yields nothing");
assert(parseRunningStreams("[]").length === 0, "an empty dump yields nothing");

assert(pageCount(516, 284, 290) === 2, "two pages when the overflow fits in one step");
assert(pageCount(900, 284, 290) === 4, "more pages as the overflow grows");
assert(pageCount(284, 284, 290) === 1, "a row that fits is one page");
assert(pageCount(100, 0, 290) === 1, "an unsized row is one page");
assert(pageCount(516, 284, 0) === 1, "a zero step is one page");

assert(pageOffset(0, 516, 284, 290) === 0, "the first page is not offset");
assert(pageOffset(1, 516, 284, 290) === 232, "the last page clamps to the end of the row");
assert(pageOffset(9, 516, 284, 290) === 232, "a page past the end still clamps");
assert(pageOffset(-3, 516, 284, 290) === 0, "a negative page does not move back");
assert(pageOffset(1, 900, 284, 290) === 290, "a middle page steps by exactly one page");

assert(calculate("2+2*2") === 6, "multiplication binds tighter than addition");
assert(calculate("(2+2)*2") === 8, "parentheses change the order");
assert(calculate("2^10") === 1024, "powers work");
assert(calculate("2^3^2") === 512, "powers are right associative");
assert(calculate("-3+1") === -2, "unary minus works");
assert(calculate("10/4") === 2.5, "division works");
assert(calculate("10%3") === 1, "modulo works");
assert(calculate("sqrt(16)") === 4, "functions work");
assert(Math.abs(calculate("pi") - Math.PI) < 1e-9, "constants work");
assert(calculate("2+") === null, "a dangling operator has no result");
assert(calculate("1/0") === null, "division by zero has no result");
assert(calculate("") === null, "an empty expression has no result");
assert(calculate("2*foo") === null, "an unknown name has no result");
assert(calculate("alert(1)") === null, "an unknown function has no result");
assert(calculate("()") === null, "empty parentheses have no result");
assert(calculate("2+3)") === null, "an unbalanced parenthesis has no result");
assert(formatNumber(0.1 + 0.2) === "0.3", "floating point noise is trimmed");
assert(formatNumber(1 / 3) === "0.333333", "results are rounded to six decimals");
assert(formatNumber(null) === "", "no value formats to nothing");

assert(detectPrefix("$git log", { files: ".", clipboard: "$" }).mode === "clipboard", "the clipboard prefix is detected");
assert(detectPrefix("$git log", { files: ".", clipboard: "$" }).text === "git log", "the prefix is stripped from the query");
assert(detectPrefix(".doc", { files: ".", clipboard: "$" }).mode === "files", "the file prefix is detected");
assert(detectPrefix("firefox", { files: ".", clipboard: "$" }).mode === "", "a plain query has no mode");
assert(detectPrefix("2+2", { files: ".", clipboard: "$" }).mode === "", "a calculation needs no prefix");
assert(detectPrefix(".", {}).mode === "", "with no marks nothing is a prefix");
assert(detectPrefix("", { files: "." }).text === "", "an empty query stays empty");

assert(fuzzyScore("Firefox", "ffx") !== null, "a subsequence matches");
assert(fuzzyScore("Firefox", "zzz") === null, "a missing subsequence does not match");
assert(fuzzyScore("fire", "fire") === 1000, "an exact match wins");
assert(fuzzyScore("Firefox", "fire") > fuzzyScore("Firmware updater", "fire"), "a tight prefix beats a scattered one");
assert(entryScore({ name: "Firefox", keywords: ["firefox"] }, "ffx") !== null, "keywords are searched too");

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

const listing = parseClipboardList("12\thello world\n9\tsecond entry\nnot a line\n");
assert(listing.length === 2, "every cliphist line is one entry");
assert(listing[0].id === "12" && listing[0].text === "hello world", "the cliphist id and preview are split");
assert(listing[1].text === "second entry", "the second entry is kept");
assert(parseClipboardList("").length === 0, "an empty listing has no entries");
assert(parseClipboardList("\t\n5\t\n").length === 0, "a line without a preview is dropped");

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
assert(appEntries({ firefox: { name: "Firefox", exec: "firefox" }, broken: {} }).length === 1, "an entry without a name or exec is skipped");
assert(appEntries({ hidden: { name: "Hidden", exec: "hidden", hidden: true } }).length === 0, "a hidden entry is skipped");
assert(appEntries({ firefox: { name: "Firefox", exec: "firefox" } })[0].id === "app:firefox", "the entry id is namespaced");
assert(appEntries({ avahi: { name: "Avahi", exec: "avahi" } }, ["avahi"]).length === 0, "an ignored app is skipped");
assert(appEntries({ keep: { name: "Keep", exec: "keep" } }, ["avahi"]).length === 1, "only the ignored ids are skipped");
assert(appEntries({ firefox: { name: "Firefox", exec: "firefox", execLine: "firefox --new-window" } })[0].execLine === "firefox --new-window", "the exec line reaches the launcher entry");

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

const mem = parseMeminfo("MemTotal:       32763188 kB\nMemFree:        26602464 kB\nMemAvailable:   28637116 kB\nBuffers:          106552 kB\nCached:          2406664 kB\nSwapTotal:       8388604 kB\nSwapFree:        7340032 kB\n");
assert(mem.total === 32763188 && mem.used === 32763188 - 28637116, "used is total minus available");
assert(mem.available === 28637116 && mem.cached === 2406664 && mem.buffers === 106552, "available, cached and buffers are read back");
assert(mem.swapUsed === 8388604 - 7340032, "swap used is total minus free");
assert(mem.pool === 32763188 + 8388604 && mem.committed === (32763188 - 28637116) + (8388604 - 7340032), "the pool and the committed amount both count swap");
assert(Math.round(mem.free) === Math.round(mem.pool - mem.committed - mem.cached - mem.buffers), "free is what is left of the pool after committed, cached and buffers");
assert(mem.free === mem.ramFree + mem.swapFree, "the free total is the ram free plus the swap free");
assert(mem.ramFree === mem.total - mem.used - mem.cached - mem.buffers, "ram free leaves out the swap");
assert(mem.swapFree === mem.swapTotal - mem.swapUsed, "swap free is the unused part of the swap");
assert(Math.round(mem.pct * 100) === Math.round(10000 * mem.committed / mem.pool), "the percentage is committed over the pool");

const noAvailable = parseMeminfo("MemTotal: 1000 kB\nMemFree: 400 kB\nBuffers: 100 kB\nCached: 200 kB\n");
assert(noAvailable.available === 700 && noAvailable.used === 300, "without MemAvailable the kernel's fallback sum is used");
assert(noAvailable.pool === 1000 && noAvailable.free === 400, "without swap the pool is just the ram");
assert(parseMeminfo("").pct === 0 && parseMeminfo("").total === 0, "an unreadable meminfo has no percentage");
assert(parseMeminfo("MemTotal: 0 kB").pct === 0, "a zero total does not divide by zero");
assert(mem.swapTotal === 8388604 && parseMeminfo("MemTotal: 100 kB").swapUsed === 0, "no swap means no swap used");
assert(parseMeminfo("MemTotal: 1000 kB\nSwapTotal: 1000 kB\nMemFree: 1000 kB\n").free === 1000, "swap free is counted as free memory too");

assert(dangerColor("#7bd88f", "#d8b04a", "#e05252", 60, 85, 0) === "#ff7bd88f", "no load is the safe colour");
assert(dangerColor("#7bd88f", "#d8b04a", "#e05252", 60, 85, 60) === "#ffd8b04a", "the warning colour lands exactly at the warning mark");
assert(dangerColor("#7bd88f", "#d8b04a", "#e05252", 60, 85, 90) === "#ffe05252", "above the danger mark it stays the danger colour");
assert(dangerColor("#7bd88f", "#d8b04a", "#e05252", 60, 85, 30) === mixColors("#7bd88f", "#d8b04a", 0.5), "below the warning mark it ramps from safe to warn");
assert(dangerColor("#7bd88f", "#d8b04a", "#e05252", 60, 85, 72.5) === mixColors("#d8b04a", "#e05252", 0.5), "between the marks it ramps from warn to danger");
assert(gbText(1024 * 1024) === "1.0 GB", "kilobytes become gigabytes");
assert(gbText(32763188) === "31.2 GB", "a real total formats to one decimal");

assert(sizeText(1024 * 1024) === "1.0 GB" && sizeText(1024 * 1024 * 3.5) === "3.5 GB", "a gigabyte or more is shown in GB");
assert(sizeText(1024 * 1024 - 1) === "1024.0 MB" && sizeText(620 * 1024) === "620.0 MB", "below a gigabyte it drops to MB");
assert(sizeText(999) === "999 KB" && sizeText(0) === "0 KB", "below a megabyte it stays in KB");

const layout = parseBarLayout(JSON.stringify({ version: 1, bar: { position: "bottom", transparent: true, centerAnchor: "date", layout: { left: [{ id: "workspaces" }, { id: "spacer", size: 12 }], center: [{ id: "clock", format: "HH:mm" }], right: [{ id: "date" }] } } }));
assert(layout.position === "bottom" && layout.transparent === true, "the bar position and the transparent flag are read");
assert(layout.centerAnchor === "date", "centerAnchor names the item the center is pinned to");
assert(layout.left.length === 2 && layout.left[1].size === 12, "the slots keep the entries and their own settings");
assert(layout.center[0].format === "HH:mm", "an entry can carry a format");
assert(layout.right.length === 1 && layout.right[0].id === "date", "the right slot is read on its own");

const defaultLayout = parseBarLayout("");
assert(defaultLayout.position === "top" && defaultLayout.left[0].id === "workspaces", "a missing file falls back to the default layout");
assert(defaultLayout.right.map(function (entry) { return entry.id; }).join(",") === "tray,notify,cpu,memory,volume,github", "the default right slot is the layout this bar has always had");
assert(parseBarLayout("{ broken").center[0].id === "clock", "a broken file falls back to the default layout");
assert(parseBarLayout('{"bar": {"layout": {"left": "nope"}}}').left[0].id === "workspaces", "a slot that is not a list falls back to the default");
assert(parseBarLayout('{"bar": {"layout": {"left": []}}}').left.length === 0, "an empty slot is left empty, not filled with the default");
assert(parseBarLayout('{"bar": {"layout": {"left": [{"name": "x"}, 3, {"id": "tray"}]}}}').left.length === 1, "entries without an id are dropped");
assert(parseBarLayout('{"bar": {"position": "left"}}').position === "top", "a position that is neither top nor bottom is top");

assert(plainText("<b>hi</b> &amp; <i>there</i><br>line") === "hi & there line", "markup is stripped from a notification body");
assert(plainText("") === "" && plainText(null) === "", "an empty body stays empty");

const contributions = parseContributions([
	'<td data-date="2026-09-11" data-level="1"></td><tool-tip>3 contributions on September 11th.</tool-tip>',
	'<td data-date="2026-09-12" data-level="4"></td><tool-tip>No contributions on September 12th.</tool-tip>',
	'<h2>599\n      contributions\n        in the last year</h2>'
].join("\n"));

assert(contributions.days.length === 2, "one row per tile");
assert(contributions.days[0].count === 3 && contributions.days[0].level === 1, "the tooltip gives the day its count");
assert(contributions.days[1].count === 0 && contributions.days[1].level === 4, "no contributions is a count of zero, not a missing day");
assert(contributions.total === 599, "the year total is read");
assert(parseContributions("").days.length === 0 && parseContributions(null).total === 0, "an empty feed parses to nothing");

const contribCells = contribGrid([
	{ date: "2026-09-07", level: 1, count: 1 },
	{ date: "2026-09-11", level: 2, count: 4 },
	{ date: "2026-09-12", level: 3, count: 9 }
], 2);

assert(contribCells.length === 14, "the grid is always 7 rows by the requested weeks");
assert(contribCells.filter(Boolean).length === 3, "only the days that were fetched take a cell");
assert(contribCells[6 * 2 + 1].count === 9, "the last day lands on its weekday row, in the last column");
assert(contribCells[1 * 2 + 1].count === 1 && contribCells[5 * 2 + 1].count === 4, "the same week keeps one column, one row per weekday");
assert(contribGrid([], 13).length === 91, "an empty feed still returns a full empty grid");

const weekCells = contribGrid([
	{ date: "2026-09-13", level: 1, count: 1 },
	{ date: "2026-09-14", level: 2, count: 4 },
	{ date: "2026-09-05", level: 1, count: 2 },
	{ date: "2026-09-06", level: 3, count: 7 }
], 3);

assert(weekCells[0 * 3 + 2].count === 1 && weekCells[1 * 3 + 2].count === 4, "a week fills from its sunday down the newest column");
assert(weekCells[0 * 3 + 1].count === 7 && weekCells[6 * 3 + 0].count === 2, "a roll is a calendar week: saturday the 5th stays in its own week, not the one after it");
assert(weekIndex(new Date("2023-12-31T00:00:00")) !== weekIndex(new Date("2023-12-30T00:00:00")), "a roll turns over on sunday (2023-12-31 is a sunday)");

const rollDays = [
	{ date: "2026-09-13", level: 1, count: 1 },
	{ date: "2026-09-14", level: 2, count: 4 }
];
const rollNow = contribGrid(rollDays, 3, "2026-09-15");
const rollNext = contribGrid(rollDays, 3, "2026-09-22");

assert(rollNow[0 * 3 + 2].count === 1 && rollNow[1 * 3 + 2].count === 4, "the days of this week land in the last roll");
assert(rollNext[0 * 3 + 1].count === 1 && rollNext[1 * 3 + 1].count === 4, "a week later the same days sit one roll further left");
assert(rollNext[0 * 3 + 2] === null && rollNext[1 * 3 + 2] === null, "the new roll starts empty, not with placeholder boxes");

const rollKept = contribGrid([
	{ date: "2026-08-30", level: 4, count: 9 },
	{ date: "2026-09-13", level: 1, count: 1 }
], 2, "2026-09-08");
const rollDropped = contribGrid([
	{ date: "2026-08-30", level: 4, count: 9 },
	{ date: "2026-09-13", level: 1, count: 1 }
], 2, "2026-09-15");

assert(rollKept[0].count === 9, "a day still inside the window keeps its cell");
assert(rollDropped.filter(function (cell) { return cell && cell.count === 9; }).length === 0, "a week later the oldest roll is dropped");
assert(contribGrid(rollDays, 3, "2026-09-15").filter(function (cell) { return cell !== null; }).length === 2, "only the days that happened get a cell");
assert(weekIndex(new Date("2024-01-06T00:00:00")) === weekIndex(new Date("2023-12-31T00:00:00")), "sunday through saturday are one roll");

const partialWeek = contribGrid([
	{ date: "2026-09-13", level: 1, count: 1 },
	{ date: "2026-09-14", level: 4, count: 44 },
	{ date: "2026-09-15", level: 0, count: 0 },
	{ date: "2026-09-16", level: 0, count: 0 }
], 3, "2026-09-14");

assert(partialWeek.filter(Boolean).length === 2, "days after today never take a cell");
assert(partialWeek[0 * 3 + 2].date === "2026-09-13" && partialWeek[1 * 3 + 2].date === "2026-09-14", "the current roll holds only its sunday and monday");

const scrambled = contribGrid([
	{ date: "2026-09-14", count: 2 },
	{ date: "2026-09-06", count: 1 }
], 2);

assert(scrambled[1 * 2 + 1].count === 2 && scrambled[0].count === 1, "a feed in any order still lands on its own weekday and week");

const degrees = splitTemp("86°F");

assert(degrees.value === "86" && degrees.unit === "°F", "the temperature splits so the unit can be drawn smaller");
assert(splitTemp("3°C").value === "3" && splitTemp("3°C").unit === "°C", "a celsius reading splits the same way");
assert(splitTemp("0").value === "0" && splitTemp("0").unit === "", "a temperature with no unit keeps its number");
assert(splitTemp("").value === "" && splitTemp("").unit === "", "no temperature splits into nothing");

const geo = parseWeatherGeo(JSON.stringify({
	results: [
		{ name: "Springfield", admin1: "Massachusetts", country: "United States", country_code: "US", latitude: 42.1, longitude: -72.59 },
		{ name: "Springfield", admin1: "Illinois", country: "United States", country_code: "US", latitude: 39.78, longitude: -89.65 }
	]
}), "IL");

assert(geo.lat === 39.78 && geo.lon === -89.65, "the region hint picks the second Springfields over the first");
assert(geo.place === "Springfield, Illinois", "the resolved place is what the card shows");
assert(parseWeatherGeo("{\"results\":[]}", "IL") === null && parseWeatherGeo("not json", "") === null, "a lookup that finds nothing is not a location");
assert(parseWeatherGeo(JSON.stringify({ results: [{ name: "Reykjavik", admin1: "Capital Region", latitude: 64.1, longitude: -21.9 }] }), "Capital").place === "Reykjavik, Capital Region", "the region hint also matches the area name");
assert(parseWeatherGeo(JSON.stringify({ results: [{ name: "Springfield", admin1: "Massachusetts", latitude: 42.1, longitude: -72.6 }] }), "IL").lat === 42.1, "when the region is nowhere in the results the first one is used");

assert(parseCoords("39.78,-89.65").lat === 39.78 && parseCoords(" 12 , -3.5 ").lon === -3.5, "coordinates in the config skip the lookup");
assert(parseCoords("Springfield, IL") === null && parseCoords("") === null, "a place name is not a coordinate pair");

assert(weatherGeoUrl("Springfield, IL").indexOf("name=Springfield") > 0, "only the city part of the config goes into the lookup");
assert(weatherGeoUrl("Springfield, IL").indexOf("count=8") > 0, "the lookup asks for enough candidates to find the right region");
assert(weatherForecastUrl(1, 2).indexOf("latitude=1&longitude=2") > 0, "the forecast is asked for the resolved coordinates");
assert(weatherForecastUrl(1, 2).indexOf("weather_code") > 0, "the forecast asks for the condition code");

const current = parseWeatherCurrent(JSON.stringify({
	current_units: { temperature_2m: "°F", wind_speed_10m: "mp/h" },
	current: { temperature_2m: 77.4, apparent_temperature: 86.2, relative_humidity_2m: 89, wind_speed_10m: 3.5, weather_code: 63, precipitation: 1.2 }
}));

assert(current.code === 63 && current.precip === 1.2 && current.temp === "77°F", "the open meteo response becomes the temperature");
assert(current.feels === "86°F" && current.wind === "4mph" && current.humidity === "89%", "feels, wind and humidity come out of the same response");
assert(parseWeatherCurrent("{}") === null && parseWeatherCurrent("nope") === null, "a response with no current block is no weather");
assert(parseWeatherCurrent(JSON.stringify({ current: { temperature_2m: 70, apparent_temperature: 70, relative_humidity_2m: 50, wind_speed_10m: 1, weather_code: 0 } })).precip === 0, "no precipitation field reads as dry");

assert(weatherCodeFor(3, 0) === 3, "overcast and dry stays overcast");
assert(weatherCodeFor(3, 0.4) === 61, "overcast and wet is rain, whatever the model code says");
assert(weatherCodeFor(0, 2) === 61, "a clear code with water coming down is rain too");
assert(weatherCodeFor(63, 1) === 63 && weatherCodeFor(95, 3) === 95, "a code that already says rain keeps its own severity");

assert(weatherCodeInfo(63, Config.weatherCodes, "?").glyph === "\u{f0597}" && weatherCodeInfo(63, Config.weatherCodes, "?").name === "Rain", "code 63 is rain and draws the rainy glyph");
assert(weatherCodeInfo(0, Config.weatherCodes, "?").glyph === "\u{f0599}", "a clear sky draws the sun");
assert(weatherCodeInfo(95, Config.weatherCodes, "?").glyph === "\u{f0593}" && weatherCodeInfo(96, Config.weatherCodes, "?").glyph === "\u{f067e}", "a plain thunderstorm and a hailstorm are different glyphs");
assert(weatherCodeInfo(1234, Config.weatherCodes, "?").glyph === "?" && weatherCodeInfo(1234, Config.weatherCodes, "?").name === "", "a code nobody mapped falls back");
assert(Config.weatherCodes[3].glyph !== Config.weatherCodes[63].glyph, "overcast and rain are not the same icon");

const pointsText = JSON.stringify({ properties: { observationStations: "https://api.weather.gov/gridpoints/ILX/74,47/stations" } });

assert(parseWeatherPoints(pointsText + "\n@@QS@@\n") === "https://api.weather.gov/gridpoints/ILX/74,47/stations", "a single answer parses even with the batch separator stuck on the end");
assert(parseWeatherPoints(pointsText) === "https://api.weather.gov/gridpoints/ILX/74,47/stations", "the point lookup gives the station list for those coordinates");
assert(parseWeatherPoints("{}") === null && parseWeatherPoints("Not Found") === null, "a place outside the states has no station list");

const stationIds = parseWeatherStationIds(JSON.stringify({
	features: [
		{ properties: { stationIdentifier: "KSPI" }, geometry: { coordinates: [-89.68, 39.84] } },
		{ properties: { stationIdentifier: "KPIA" }, geometry: { coordinates: [-89.69, 40.66] } },
		{ properties: { stationIdentifier: "KMDH" }, geometry: { coordinates: [-89.25, 37.78] } },
		{ properties: { stationIdentifier: "KORD" }, geometry: { coordinates: [-87.9, 41.98] } },
		{ properties: {}, geometry: { coordinates: [-72.5, 42.1] } }
	]
}), 39.7955, -89.6432, 2);

assert(stationIds.length === 2 && stationIds[0] === "KSPI" && stationIds[1] === "KPIA", "the stations are sorted by distance and capped at the configured count");
assert(parseWeatherStationIds("{}", 0, 0, 3).length === 0, "a station list with nothing in it yields no stations");

assert(weatherCodeFromText("Heavy Rain and Fog/Mist") === 65, "the station wording is what decides the condition, heavy rain first");
assert(weatherCodeFromText("Light Rain") === 61 && weatherCodeFromText("Light Drizzle") === 61, "rain and drizzle are both rain");
assert(weatherCodeFromText("Chance Showers And Thunderstorms") === 95, "a thunderstorm outranks the showers in the same sentence");
assert(weatherCodeFromText("Partly Cloudy") === 2 && weatherCodeFromText("Cloudy") === 3 && weatherCodeFromText("Clear") === 0, "cloud words and clear words stay dry");
assert(weatherCodeFromText("Mostly Cloudy") === 3 && weatherCodeFromText("Mostly Sunny") === 2, "mostly cloudy is overcast, mostly sunny is not");
assert(weatherCodeFromText("Haze") === 45 && weatherCodeFromText("Freezing Rain") === 66 && weatherCodeFromText("Blizzard") === 75, "haze, freezing rain and blizzard all land somewhere sensible");
assert(weatherCodeFromText("") === -1 && weatherCodeFromText("Volcanic Ash") === -1, "wording nobody mapped is not a condition");

const observationRows = parseWeatherObservations(JSON.stringify({ properties: { textDescription: "Haze" } }) + "@@QS@@"
	+ JSON.stringify({ properties: { textDescription: "Heavy Rain and Fog/Mist", precipitationLastHour: { value: 2.5 } } })
	+ "@@QS@@" + JSON.stringify({ properties: {} }));

assert(observationRows.length === 2 && observationRows[1].text === "Heavy Rain and Fog/Mist", "each station response in the batch is its own reading");
assert(weatherObservationCode(observationRows) === 65, "a wet station anywhere in the batch is what the card shows, not the dry one nearest to you");
assert(weatherObservationCode(parseWeatherObservations(JSON.stringify({ properties: { textDescription: "Cloudy" } }))) === 3, "with no wet station the nearest reading is used");
assert(weatherObservationCode([{ text: "Cloudy", code: 3, precip: 0.4 }]) === 61, "water measured in the last hour counts even when the wording says cloudy");
assert(weatherObservationCode([]) === -1 && weatherObservationCode([{ text: "", code: -1, precip: 0 }]) === -1, "a batch with nothing usable leaves the model code alone");

assert(weatherRequest("u1 u2").indexOf("@@QS@@") > 0 && weatherRequest("u1 u2").indexOf("u1 u2") > 0, "the batch request joins the stations and marks where each answer ends");
assert(weatherRequest("u1").indexOf("-w '") > 0, "the separator is a format string, so curl cannot mistake it for a file to read");
assert(weatherObservationUrl("KSPI").indexOf("/stations/KSPI/observations/latest") > 0, "an observation is asked for by station id");
assert(weatherPointsUrl(39.8, -89.6).indexOf("points/39.8,-89.6") > 0, "the point lookup is asked for our own coordinates");

const weatherIcons = [Config.weatherIcon, Config.weatherLoadingIcon];
const codeKeys = Object.keys(Config.weatherCodes);

for (let i = 0; i < codeKeys.length; i++) {
	weatherIcons.push(Config.weatherCodes[codeKeys[i]].glyph);
	assert(Config.weatherCodes[codeKeys[i]].name !== "", "weather code " + codeKeys[i] + " has a name");
}

for (let i = 0; i < weatherIcons.length; i++) {
	const glyph = weatherIcons[i];
	const point = glyph.codePointAt(0);

	assert(glyph.length === 2 && point >= 0xf0000 && point <= 0xf1fff, "a weather glyph is one five digit code point and not a four digit escape plus a stray character: " + JSON.stringify(glyph));
}

console.log("check ok");
