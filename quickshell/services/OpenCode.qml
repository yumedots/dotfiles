pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Talks to the OpenCode v2 server that backs the local `opencode` CLI.
//
// The service authenticates with the password the server writes into
// ~/.local/state/opencode/service.json, streams /api/event over SSE, and keeps
// a per session state map that is aggregated into one face state.
//
// It also reads the plan the CLI is signed in to. The credential lives in the
// server, so the server hands it over, and the plan's own endpoint answers
// with the windows of what is left of the allowance.
QtObject {
	id: root

	// idle | working | blocked | error
	readonly property string state: root.aggregateState
	readonly property bool connected: root.serverUrl !== ""

	property string serverUrl: ""
	property string serverPassword: ""
	property bool online: false

	// sessionID -> { status, blocked, error, title, directory, updated }
	property var sessions: ({})
	property int revision: 0

	// Details for the current face state, shown next to the face.
	readonly property string detailText: {
		root.revision;

		const ids = Object.keys(root.sessions);

		for (let i = 0; i < ids.length; i++) {
			const session = root.sessions[ids[i]];

			if (session.blocked)
				return session.blocked;

			if (session.error)
				return session.error;
		}

		return "";
	}

	readonly property string aggregateState: {
		root.revision;

		const ids = Object.keys(root.sessions);
		let hasBlocked = false;
		let hasError = false;
		let hasWorking = false;

		for (let i = 0; i < ids.length; i++) {
			const session = root.sessions[ids[i]];

			if (session.blocked)
				hasBlocked = true;

			if (session.error)
				hasError = true;

			if (session.status === "busy" || session.status === "retry")
				hasWorking = true;
		}

		if (hasBlocked || root.askingSessions.length > 0)
			return "blocked";

		if (hasError)
			return "error";

		if (hasWorking || root.runningSessions.length > 0)
			return "working";

		return "idle";
	}

	// The sessions that have work in them, one row each. Several of them can
	// be working at once, so every one of them gets a row.
	readonly property var working: {
		root.revision;

		const rows = [];
		const seen = {};

		const push = function (id, running, question, failed) {
			if (seen[id])
				return;

			seen[id] = true;

			const session = root.sessions[id] || {};

			rows.push({
				id: id,
				title: root.titleOf(id) || "session",
				icon: root.iconOf(root.providerOf(id)),
				working: running,
				question: question || root.askingSessions.indexOf(id) >= 0,
				failed: failed,
				detail: session.blocked || session.error || "",
				updated: session.updated || 0,
			});
		};

		// The sessions the shell has heard about that are working, asking a
		// question, or failed. The sub agents are left out, the session that
		// sent for them is the one that shows.
		const ids = Object.keys(root.sessions);

		for (let i = 0; i < ids.length; i++) {
			const id = ids[i];
			const session = root.sessions[id];

			if (root.isSubagent(id))
				continue;

			const busy = session.status === "busy" || session.status === "retry";
			const question = !!session.blocked;
			const failed = !!session.error;

			if (!busy && !question && !failed)
				continue;

			push(id, busy, question, failed);
		}

		// The sessions the server says are running right now, even the ones
		// the shell never heard about.
		const running = root.runningSessions;

		for (let i = 0; i < running.length; i++) {
			if (root.isSubagent(running[i]))
				continue;

			push(running[i], true, false, false);
		}

		// The ones that are working come first, then the ones asking a
		// question, then the ones that failed. Inside a group the one
		// touched last comes first.
		const rank = function (row) {
			return row.working ? 0 : (row.question ? 1 : 2);
		};

		rows.sort(function (a, b) {
			if (rank(a) !== rank(b))
				return rank(a) - rank(b);

			return b.updated - a.updated;
		});

		return rows;
	}

	// The title of a session, so a row can say what it is working on.
	function titleOf(id) {
		const session = root.sessions[id] || {};

		if (session.title)
			return session.title;

		const listed = root.findListed(id);

		return listed ? listed.title : "";
	}

	// Whether a session is a sub agent, which has a parent session.
	function isSubagent(id) {
		const listed = root.findListed(id);

		return !!listed && !!listed.parent;
	}

	// The provider a session runs on, so a row can say who is doing the work.
	function providerOf(id) {
		const session = root.sessions[id] || {};

		if (session.provider)
			return session.provider;

		const listed = root.findListed(id);

		return listed ? listed.provider : "";
	}

	// The mark of a provider, so a row can show who is doing the work.
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

	// Records what happened to a session. A session that is only listed passes
	// active false, so listing it does not count as activity.
	function touch(id, patch, active) {
		const current = root.sessions[id] || {};
		const next = Object.assign({}, current, patch);

		if (active !== false)
			next.updated = Date.now();

		root.sessions = Object.assign({}, root.sessions, (function () {
			const out = {};

			out[id] = next;

			return out;
		})());

		root.revision += 1;
	}

	// ---- server connection ----------------------------------------------------

	property FileView serviceFile: FileView {
		path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/opencode/service.json"
		blockLoading: true
		watchChanges: true

		onFileChanged: serviceFile.reload()
		onLoaded: root.readService(serviceFile.text())
	}

	function readService(text) {
		let info;

		try {
			info = JSON.parse(text);
		} catch (error) {
			return;
		}

		if (!info || !info.url || !info.password)
			return;

		root.serverUrl = info.url;
		root.serverPassword = info.password;
		root.online = true;

		// The session list is fetched here rather than from a signal on the
		// service file: the file is read before the connections object exists,
		// so its loaded signal would never be seen. The fetch waits for the
		// server url to be visible to the process.
		Qt.callLater(root.refreshSessions);
		Qt.callLater(root.fetchUsage);
	}

	property Process stream: Process {
		command: root.serverUrl === "" ? ["true"] : [
			"curl",
			"-sN",
			"-u",
			"opencode:" + root.serverPassword,
			root.serverUrl + "/api/event",
		]

		stdout: SplitParser {
			splitMarker: "\n"

			onRead: function (data) {
				const line = String(data).trim();

				if (!line.startsWith("data: "))
					return;

				let event;

				try {
					event = JSON.parse(line.substring(6));
				} catch (error) {
					return;
				}

				root.handleEvent(event);
			}
		}

		onExited: root.reconnect.restart()
	}

	property Timer reconnect: Timer {
		interval: 2000
		onTriggered: root.stream.running = true
	}

	Component.onCompleted: {
		root.stream.running = true;
	}

	function handleEvent(event) {
		const type = event.type || "";
		const data = event.data || {};
		const id = data.sessionID || data.sessionId || "";

		if (type === "session.created" || type === "session.renamed") {
			const patch = {};

			if (data.title !== undefined)
				patch.title = data.title;

			const directory = data.directory || (data.location && data.location.directory);

			if (directory !== undefined)
				patch.directory = directory;

			if (id)
				root.touch(id, patch);

			return;
		}

		if (!id)
			return;

		switch (type) {
			case "session.status":
				root.touch(id, { status: (data.status && data.status.type) || "idle" });
				break;
			case "session.execution.started":
				root.touch(id, { status: "busy", error: "" });
				break;
			case "session.execution.succeeded":
				root.touch(id, { status: "idle" });
				root.announceFinished(id);
				break;
			case "session.execution.failed":
				root.touch(id, { status: "idle", error: (data.error && data.error.message) || "failed" });
				break;
			case "session.execution.interrupted":
				root.touch(id, { status: "idle" });
				break;
			case "session.idle":
				root.touch(id, { status: "idle" });
				break;
			case "permission.asked":
				root.touch(id, { blocked: root.permissionText(data) });
				root.announceQuestion(id, root.permissionText(data));
				break;
			case "permission.replied":
				root.touch(id, { blocked: "" });
				break;
			case "form.created":
				root.touch(id, { blocked: (data.title || "question") });
				root.announceQuestion(id, data.title || "question");
				break;
			case "form.replied":
			case "form.cancelled":
				root.touch(id, { blocked: "" });
				break;
			default:
				break;
		}
	}

	function permissionText(data) {
		const action = data.action || "";
		const message = data.message || "";

		if (message)
			return message;

		if (action)
			return action;

		return "permission needed";
	}

	// The sessions that are done, newest first. A session stays in the list
	// until it is dismissed.
	property var doneSessions: []

	function announceFinished(sessionID) {
		const session = root.sessions[sessionID] || {};
		const title = session.title || "agent";

		root.doneSessions = [{ id: sessionID, title: title, at: Date.now() }].concat(root.doneSessions).slice(0, 20);

		Quickshell.execDetached([
			"notify-send",
			"-a",
			"OpenCode",
			"-t",
			"5000",
			title,
			"Task finished",
		]);
	}

	// A session that asks something needs the user, so the notification stays
	// on the screen until it is answered.
	function announceQuestion(sessionID, text) {
		const session = root.sessions[sessionID] || {};
		const title = session.title || "agent";

		Quickshell.execDetached([
			"notify-send",
			"-a",
			"OpenCode",
			"-u",
			"critical",
			"-t",
			"0",
			title,
			text,
		]);
	}

	// Takes a finished session off the list of done work.
	function dismiss(id) {
		root.doneSessions = root.doneSessions.filter(function (entry) {
			return entry.id !== id;
		});
	}

	// ---- sessions -------------------------------------------------------------
	//
	// The server knows about every session, and the titles of the ones that
	// were already running when the shell started are only in there. The list
	// is never shown, it only names the work that is going on.

	property Process listSessions: Process {
		command: root.serverUrl === "" ? ["true"] : [
			"curl",
			"-sS",
			"-u",
			"opencode:" + root.serverPassword,
			root.serverUrl + "/api/session?order=desc&limit=50",
		]

		stdout: StdioCollector {
			onStreamFinished: function () {
				let payload;

				try {
					payload = JSON.parse(this.text);
				} catch (error) {
					return;
				}

				const sessions = (payload && payload.data) || [];

				root.serverSessions = sessions.map(function (session) {
					return {
						id: session.id,
						title: session.title || "",
						provider: (session.model && session.model.providerID) || "",
						parent: session.parentID || ""
					};
				});
			}
		}
	}

	property var serverSessions: []

	// The sessions the server says are running right now.
	property var runningSessions: []

	// The sessions that are asking a question, so they wait for the user.
	property var askingSessions: []

	// The permission requests the server has open. A session that asks
	// something is one of these, so the agent can be shown waiting for the
	// user even when the question was asked before the shell started.
	property Process listPermissions: Process {
		command: root.serverUrl === "" ? ["true"] : [
			"curl",
			"-sS",
			"-u",
			"opencode:" + root.serverPassword,
			root.serverUrl + "/api/permission/request",
		]

		stdout: StdioCollector {
			onStreamFinished: function () {
				root.readPermissions(this.text);
			}
		}
	}

	function readPermissions(text) {
		let payload;

		try {
			payload = JSON.parse(text);
		} catch (error) {
			return;
		}

		const list = (payload && payload.data) || [];
		const asking = [];

		for (let i = 0; i < list.length; i++) {
			const id = list[i] && list[i].sessionID;

			if (id)
				asking.push(id);
		}

		root.askingSessions = asking;
	}

	property Process listRunning: Process {
		command: root.serverUrl === "" ? ["true"] : [
			"curl",
			"-sS",
			"-u",
			"opencode:" + root.serverPassword,
			root.serverUrl + "/api/session/active",
		]

		stdout: StdioCollector {
			onStreamFinished: function () {
				root.readRunning(this.text);
			}
		}
	}

	function readRunning(text) {
		let payload;

		try {
			payload = JSON.parse(text);
		} catch (error) {
			return;
		}

		const data = (payload && payload.data) || {};
		const ids = Object.keys(data);

		// The titles of the sessions that just came up are only in the list,
		// so the list is fetched when the set of running sessions changes.
		if (ids.length !== root.runningSessions.length || ids.some(function (id, index) {
			return id !== root.runningSessions[index];
		}))
			root.refreshSessions();

		root.runningSessions = ids;
	}

	property Timer runningTimer: Timer {
		interval: 10000
		repeat: true
		running: true
		triggeredOnStart: true

		onTriggered: {
			root.listRunning.running = true;
			root.listPermissions.running = true;
		}
	}

	function findListed(id) {
		for (let i = 0; i < root.serverSessions.length; i++) {
			if (root.serverSessions[i].id === id)
				return root.serverSessions[i];
		}

		return null;
	}

	function refreshSessions() {
		if (root.serverUrl === "")
			return;

		root.listSessions.running = true;
	}

	property Connections serviceConnections: Connections {
		target: root.serviceFile

		function onLoaded() {
			root.refreshSessions();
		}
	}

	property Timer refreshTimer: Timer {
		interval: 30000
		repeat: true
		running: true
		triggeredOnStart: true

		onTriggered: root.refreshSessions()
	}

	// ---- subscription ---------------------------------------------------------
	//
	// The plan the CLI is signed in to, and the windows of what is left of
	// its allowance. The credential is kept by the server, and the plan's own
	// endpoint answers with how full each window is.

	// The windows of the allowance: { title, percent, resetsAt }.
	property var limits: []

	// Why there is nothing to show, when the plan cannot be read.
	property string usageError: ""

	property string accessToken: ""

	property Process credential: Process {
		command: root.serverUrl === "" ? ["true"] : [
			"curl",
			"-sS",
			"-u",
			"opencode:" + root.serverPassword,
			root.serverUrl + "/api/credential",
		]

		stdout: StdioCollector {
			onStreamFinished: function () {
				root.readCredential(this.text);
			}
		}
	}

	function readCredential(text) {
		let payload;

		try {
			payload = JSON.parse(text);
		} catch (error) {
			root.usageError = "credential unreadable";
			return;
		}

		const list = (payload && payload.data) || [];
		let token = "";

		for (let i = 0; i < list.length; i++) {
			const entry = list[i];

			if (entry && entry.active && entry.value && entry.value.access)
				token = entry.value.access;
		}

		if (!token) {
			root.usageError = "not signed in";
			return;
		}

		root.accessToken = token;
		root.usage.running = true;
	}

	property Process usage: Process {
		command: root.accessToken === "" ? ["true"] : [
			"curl",
			"-sS",
			"-H",
			"Authorization: Bearer " + root.accessToken,
			"https://opencode.ai/zen/go/v1/usage",
		]

		stdout: StdioCollector {
			onStreamFinished: function () {
				root.readUsage(this.text);
			}
		}

		onExited: function (code) {
			if (code !== 0)
				root.usageError = "plan unreachable";
		}
	}

	function readUsage(text) {
		let payload;

		try {
			payload = JSON.parse(text);
		} catch (error) {
			root.usageError = "usage unreadable";
			return;
		}

		const usage = (payload && payload.usage) || {};
		const windows = [["rolling", "Session"], ["weekly", "Weekly"], ["monthly", "Monthly"]];
		const limits = [];

		for (let i = 0; i < windows.length; i++) {
			const window = usage[windows[i][0]];

			if (!window)
				continue;

			limits.push({
				title: windows[i][1],
				percent: Number(window.percent) || 0,
				resetsAt: window.resetsAt || "",
			});
		}

		if (limits.length === 0) {
			root.usageError = "no plan";
			return;
		}

		root.limits = limits;
		root.usageError = "";
	}

	function fetchUsage() {
		if (root.serverUrl === "")
			return;

		root.credential.running = true;
	}

	property Timer usageTimer: Timer {
		interval: 300000
		repeat: true
		running: true
		triggeredOnStart: true

		onTriggered: root.fetchUsage()
	}
}
