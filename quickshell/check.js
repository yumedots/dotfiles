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
	"/usr/share/applications/hidden.desktop:Name=Hidden App",
	"/usr/share/applications/hidden.desktop:Icon=hidden",
	"/usr/share/applications/hidden.desktop:NoDisplay=true"
].join("\n"));

assert(lookupApp(entries, "firefox").icon === "firefox", "id lookup");
assert(lookupApp(entries, "firefox").exec === "firefox", "exec basename comes from the first token only");
assert(lookupApp(entries, "Code - Insiders").id === "code-insiders", "wmclass lookup");
assert(lookupApp(entries, "code-insiders").icon === "vscode-insiders", "action groups do not overwrite the main icon");
assert(lookupApp(entries, "foo bar").id === "foo", "display name lookup");
assert(lookupApp(entries, "hidden") === null, "NoDisplay entries are skipped");
assert(lookupApp(entries, "nope") === null, "unknown ids return null");
assert(lookupApp(entries, "") === null, "empty names return null");
assert(filledCells(50, 15) === 8 && filledCells(200, 15) === 15, "filled cells clamp");
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

console.log("check ok");
