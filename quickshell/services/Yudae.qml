pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// The daemon's state, read over its unix socket. Everything here is a view of
// what yudaemond already worked out: the agent state, the sessions, the plans,
// the done list and the pointer. Nothing is fetched or parsed here.
QtObject {
	id: root

	readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/yudaemond.sock"

	// Whether the socket to the daemon is up.
	property bool connected: false

	// The last full snapshot the daemon sent.
	property var snapshot: ({})

	// The pointer position, for the face to look at.
	property var cursor: ({ valid: false, x: 0, y: 0 })

	readonly property var opencode: root.snapshot.opencode || ({})
	readonly property var codex: root.snapshot.codex || ({})

	readonly property string state: root.opencode.state || "idle"
	readonly property string detailText: root.opencode.detail || ""
	readonly property string usageError: root.opencode.usageError || ""
	readonly property string codexError: root.codex.failure || ""
	readonly property bool online: root.opencode.connected === true

	readonly property string planError: root.usageError !== "" ? root.usageError : root.codexError

	readonly property var doneSessions: root.opencode.done || []

	readonly property var plans: {
		const out = [];
		const own = root.opencode.plan;

		if (own && own.limits && own.limits.length > 0)
			out.push({ title: Config.agentPlanName, icon: Config.agentPlanIcon, limits: own.limits, error: "" });

		const other = root.codex;

		if (other.limits && other.limits.length > 0)
			out.push({
				title: "ChatGPT" + (other.plan ? " " + other.plan.charAt(0).toUpperCase() + other.plan.substring(1) : ""),
				icon: "",
				limits: other.limits,
				error: "",
			});

		return out;
	}

	readonly property var sessions: root.opencode.sessions || []
	readonly property var running: root.opencode.running || []
	readonly property var asking: root.opencode.asking || []

	// The sessions with work in them, one row each: working, asking, or failed.
	// Sub agents are left out, the session that sent for them shows instead.
	readonly property var working: {
		const rows = [];
		const seen = {};

		const push = function (id, running, question, failed) {
			if (seen[id])
				return;

			seen[id] = true;

			const session = root.sessionOf(id) || {};

			rows.push({
				id: id,
				title: session.title || "session",
				icon: root.iconOf(session.provider || ""),
				working: running,
				question: question || root.asking.indexOf(id) >= 0,
				failed: failed,
				detail: session.blocked || session.failure || "",
				updated: session.updated || 0,
			});
		};

		for (let i = 0; i < root.sessions.length; i++) {
			const session = root.sessions[i];

			if (session.parent)
				continue;

			const busy = session.status === "busy" || session.status === "retry";
			const question = !!session.blocked;
			const failed = !!session.failure;

			if (!busy && !question && !failed)
				continue;

			push(session.id, busy, question, failed);
		}

		for (let i = 0; i < root.running.length; i++) {
			const id = root.running[i];
			const session = root.sessionOf(id);

			if (session && session.parent)
				continue;

			push(id, true, false, false);
		}

		const rank = function (row) {
			return row.working ? 0 : (row.question ? 1 : 2);
		};

		rows.sort(function (a, b) {
			if (rank(a) !== rank(b))
				return rank(a) - rank(b);

			return b.updated - a.updated;
		});

		let failures = 0;

		return rows.filter(function (row) {
			if (!row.failed)
				return true;

			failures += 1;

			return failures <= 3;
		});
	}

	function sessionOf(id) {
		for (let i = 0; i < root.sessions.length; i++)
			if (root.sessions[i].id === id)
				return root.sessions[i];

		return null;
	}

	function iconOf(providerID) {
		const id = String(providerID || "").toLowerCase();

		if (!id)
			return "";

		if (id.indexOf("opencode") >= 0 || id.indexOf("zen") >= 0)
			return "opencode";

		if (id.indexOf("anthropic") >= 0 || id.indexOf("claude") >= 0)
			return "claude";

		if (id.indexOf("azure") >= 0)
			return "microsoftazure";

		if (id.indexOf("openai") >= 0 || id.indexOf("codex") >= 0)
			return "openai";

		if (id.indexOf("google") >= 0 || id.indexOf("gemini") >= 0 || id.indexOf("vertex") >= 0)
			return "google";

		if (id.indexOf("copilot") >= 0)
			return "githubcopilot";

		if (id.indexOf("grok") >= 0 || id.indexOf("xai") >= 0)
			return "x";

		if (id.indexOf("openrouter") >= 0)
			return "openrouter";

		if (id.indexOf("mistral") >= 0)
			return "mistralai";

		if (id.indexOf("deepseek") >= 0)
			return "deepseek";

		if (id.indexOf("kimi") >= 0 || id.indexOf("moonshot") >= 0)
			return "kimi";

		if (id.indexOf("qwen") >= 0 || id.indexOf("alibaba") >= 0)
			return "alibabacloud";

		if (id.indexOf("perplexity") >= 0)
			return "perplexity";

		if (id.indexOf("ollama") >= 0)
			return "ollama";

		if (id.indexOf("huggingface") >= 0)
			return "huggingface";

		if (id.indexOf("bedrock") >= 0 || id.indexOf("amazon") >= 0)
			return "amazonaws";

		if (id.indexOf("nvidia") >= 0)
			return "nvidia";

		return "";
	}

	property bool gazeWanted: false

	function watchGaze(flag) {
		root.gazeWanted = flag === true;
		root.send({ gaze: root.gazeWanted });
	}

	readonly property var weatherState: root.snapshot.weather || ({})

	readonly property var screenState: root.snapshot.screen || ({})
	readonly property var screenMonitors: root.screenState.monitors || []
	readonly property int screenPrimary: root.screenState.primary || 0
	readonly property var screenActive: root.screenMonitors[root.screenPrimary] || null
	readonly property var networkState: root.snapshot.network || ({})
	readonly property var network: root.networkState

	readonly property var settingsState: root.snapshot.settings || ({})
	readonly property int settingsFontSize: root.settingsState.fontSize || 0
	readonly property int settingsIconSize: root.settingsState.iconSize || 0
	readonly property string settingsRecord: root.settingsState.record || ""

	readonly property var screenPanel: root.screenState.panel || ({})
	readonly property var screenGroups: root.screenPanel.groups || []
	readonly property string screenRaw: root.screenState.raw || ""

	function networkScan() {
		root.send({ cmd: { network: { scan: true } } });
	}

	function networkConnect(ssid, password) {
		root.send({ cmd: { network: { connect: { ssid: ssid, password: password || "" } } } });
	}

	function networkDns(connection, servers) {
		root.send({ cmd: { network: { dns: { connection: connection, servers: servers } } } });
	}

	function networkSpeedTest() {
		root.send({ cmd: { network: { speed: true } } });
	}

	function networkSpeedCancel() {
		root.send({ cmd: { network: { speedCancel: true } } });
	}

	function screenKey(code) {
		root.send({ cmd: { screen: { keyCode: code } } });
	}

	function screenPick(kind, value) {
		root.send({ cmd: { screen: { pick: { kind: kind, value: value } } } });
	}

	function screenDetect() {
		root.send({ cmd: { screen: { detect: true } } });
	}

	readonly property var icons: root.snapshot.icons || ({})
	readonly property var bar: root.snapshot.bar || ({})
	readonly property var wallpaper: root.snapshot.wallpaper || ({})

	function wallpaperApply(path, band) {
		root.send({ cmd: { wallpaper: { apply: { path: path, band: band || 0 } } } });
	}

	function wallpaperScan() {
		root.send({ cmd: { wallpaper: { scan: true } } });
	}

	readonly property var audio: root.snapshot.audio || ({})
	readonly property var audioNodes: root.audio.nodes || []

	function audioVolume(id, level) {
		root.send({ cmd: { audio: { volume: { id: id, level: level } } } });
	}

	function audioMute(id, muted) {
		root.send({ cmd: { audio: { mute: { id: id, muted: muted } } } });
	}

	function audioDefault(id) {
		root.send({ cmd: { audio: { default: { id: id } } } });
	}

	function audioWatch(on) {
		root.send({ cmd: { audio: { watch: { on: on === true } } } });
	}

	readonly property var appsEntries: (root.snapshot.apps && root.snapshot.apps.entries) || ({})
	readonly property var systemState: root.snapshot.system || ({})
	readonly property var system: root.systemState

	function systemCommand(message) {
		root.send({ cmd: { system: message } });
	}

	function weather(message) {
		root.send({ cmd: { weather: message } });
	}

	function dismiss(id) {
		root.send({ dismiss: id });
	}

	function fetchUsage() {
		root.send({ refresh: true });
	}

	function fetchCodex() {
		root.send({ refresh: true });
	}

	function iconsWant(names) {
		root.send({ cmd: { icons: { want: names } } });
	}

	function iconsWantPid(pid) {
		root.send({ cmd: { icons: { pid: pid } } });
	}

	function send(message) {
		if (!root.socket.connected)
			return;

		root.socket.write(JSON.stringify(message) + "\n");
	}

	function receive(line) {
		const text = String(line).trim();

		if (text === "")
			return;

		let message;

		try {
			message = JSON.parse(text);
		} catch (error) {
			return;
		}

		if (message.t === "gaze") {
			root.cursor = { valid: true, x: message.x, y: message.y };
			return;
		}

		root.snapshot = message;
	}

	property Socket socket: Socket {
		path: root.socketPath

		parser: SplitParser {
			splitMarker: "\n"

			onRead: function (line) { root.receive(line); }
		}

		onConnectedChanged: {
			root.connected = root.socket.connected;

			if (root.socket.connected) {
				root.send({ sync: true });

				if (root.gazeWanted)
					root.send({ gaze: true });
			}
		}
	}

	// The daemon may start, restart or stop at any time. Reconnecting on a
	// timer keeps the bar in step without anything else watching the socket.
	property Timer retry: Timer {
		interval: 1000
		running: true
		repeat: true

		onTriggered: if (!root.socket.connected)
			root.socket.connected = true
	}

	Component.onCompleted: root.socket.connected = true
}
