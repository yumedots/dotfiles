const fs = require("fs");

eval(fs.readFileSync(__dirname + "/helpers.js", "utf8").replace(".pragma library", ""));

function assert(condition, message) {
	if (!condition)
		throw new Error(message);
}

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
assert(mondayIndex(new Date(2024, 0, 1)) === 0, "2024-01-01 is a monday");
assert(mondayIndex(new Date(2026, 8, 1)) === 1, "2026-09-01 is a tuesday");
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
assert(nextIndex(["a", "b", "c"], "a") === 1, "next window");
assert(nextIndex(["a", "b", "c"], "c") === 0, "window cycling wraps around");
assert(nextIndex(["a", "b", "c"], "zz") === 0, "an unfocused app starts at its first window");
assert(nextIndex(["only"], "only") === 0, "a single window cycles to itself");
assert(nextIndex([], "a") === -1, "no windows");

const win = function (ws, x, y) { return { workspace: { id: ws }, lastIpcObject: { at: [x, y] } }; };
const left = win(3, 100, 0);
const right = win(3, 900, 0);
const above = win(3, 100, 400);
const elsewhere = win(9, 50, 0);

assert(orderedWindows([right, left, elsewhere], 3)[0] === left, "the leftmost window on this workspace comes first");
assert(orderedWindows([right, left, elsewhere], 3)[2] === elsewhere, "windows on other workspaces come last");
assert(orderedWindows([right, elsewhere, left], 3)[1] === right, "same column falls through to the next window");
assert(orderedWindows([above, left], 3)[0] === left, "same x orders by y");
assert(orderedWindows([elsewhere], 3).length === 1, "a single window stays put");

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
assert(defaultLayout.right.map(function (entry) { return entry.id; }).join(",") === "tray,cpu,memory,volume,date", "the default right slot is the layout this bar has always had");
assert(parseBarLayout("{ broken").center[0].id === "clock", "a broken file falls back to the default layout");
assert(parseBarLayout('{"bar": {"layout": {"left": "nope"}}}').left[0].id === "workspaces", "a slot that is not a list falls back to the default");
assert(parseBarLayout('{"bar": {"layout": {"left": []}}}').left.length === 0, "an empty slot is left empty, not filled with the default");
assert(parseBarLayout('{"bar": {"layout": {"left": [{"name": "x"}, 3, {"id": "tray"}]}}}').left.length === 1, "entries without an id are dropped");
assert(parseBarLayout('{"bar": {"position": "left"}}').position === "top", "a position that is neither top nor bottom is top");

console.log("check ok");
