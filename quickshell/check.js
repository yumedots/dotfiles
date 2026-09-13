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
assert(launchCommand({ exec: "btop", terminal: true }, "btop")[0] === "foot" && launchCommand({ exec: "btop", terminal: true }, "btop")[2] === "btop", "a Terminal=true app opens inside a terminal");
assert(launchCommand({ exec: "code-insiders" }, "code-insiders")[0] === "code-insiders", "a regular app runs directly");
assert(launchCommand(null, "footclient")[0] === "footclient", "an entry-less app runs as-is");
assert(togglePin([], "yazi")[0] === "yazi", "pin adds to an empty list");
assert(togglePin(["a", "b"], "c").length === 3, "pin keeps the rest");
assert(togglePin(["a", "b"], "b").length === 1, "pin removes what is pinned");
assert(togglePin(["a", "b"], "B").length === 1, "pin removal is case-insensitive");
assert(pinnedFromText("yazi\nbtop\n\n")[0] === "yazi" && pinnedFromText("yazi\nbtop\n\n").length === 2, "pin file lines are trimmed and blanks dropped");
assert(pinnedFromText("").length === 0, "a missing pin file yields nothing");
assert(shellQuote("a b") === "'a b'", "shell quoting wraps spaces");

const animations = JSON.stringify([[
	{ name: "windowsIn", overridden: true, speed: 1.6 },
	{ name: "fade", overridden: false, speed: 0 }
]]);

assert(parseHyprAnimationSpeed(animations, "windowsIn") === 160, "an overridden animation speed becomes milliseconds");
assert(parseHyprAnimationSpeed(animations, "fade") === null, "an inherited animation has no own speed");
assert(parseHyprAnimationSpeed(animations, "nope") === null, "an unknown leaf has no speed");
assert(parseHyprAnimationSpeed("not json", "windowsIn") === null, "garbage yields nothing");

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

console.log("check ok");
