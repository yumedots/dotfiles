pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Talks to the OpenCode v2 server that backs the local `opencode` CLI.
//
// The service authenticates with the password the server writes into
// ~/.local/state/opencode/service.json, streams /api/event over SSE, and keeps a
// per session state map that is aggregated into one face state.
QtObject {
	id: root

	// idle | working | blocked | error
	readonly property string state: root.aggregateState
	readonly property bool connected: root.serverUrl !== ""

	// The session the input line sends to. The agent that is working wins, or
	// else the one that was touched last.
	readonly property string targetSession: Agent.pickTarget(root.sessions)

	// The title of any session, so a panel can show the one it locked onto.
	function titleOf(id) {
		const session = root.sessions[id] || {};

		return session.title || "";
	}

	// Details for the current face state, shown next to the face.
	readonly property string detail: root.detailText

	property string serverUrl: ""
	property string serverPassword: ""
	property bool online: false

	// sessionID -> { status, blocked, error, title, directory, updated }
	property var sessions: ({})
	property int revision: 0

	readonly property var aggregateState: {
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

		if (hasBlocked)
			return "blocked";

		if (hasError)
			return "error";

		if (hasWorking)
			return "working";

		return "idle";
	}

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

			if (data.directory !== undefined)
				patch.directory = data.directory;

			if (data.id)
				root.touch(data.id, patch);

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
				break;
			case "permission.replied":
				root.touch(id, { blocked: "" });
				break;
			case "form.created":
				root.touch(id, { blocked: (data.title || "question") });
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

	function announceFinished(sessionID) {
		const session = root.sessions[sessionID] || {};
		const title = session.title || "agent";

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

	// ---- sending --------------------------------------------------------------

	// Emitted when a message reached the server.
	signal sent(string text)

	// Why the last send did not go through, shown by the panel.
	property string sendError: ""

	property bool sending: false
	property string pendingText: ""
	property string sendSession: ""
	property string sendBody: ""

	// Sends a message to a session. A session id of "" means the current
	// target. The text is kept by the caller until the send succeeds.
	function send(text, sessionID) {
		const body = String(text || "").trim();

		if (!body)
			return false;

		const target = sessionID || root.targetSession;

		if (!root.serverUrl) {
			root.sendError = "OpenCode offline";
			return false;
		}

		if (!target) {
			root.sendError = "no agent session";
			return false;
		}

		root.sendError = "";

		if (root.sending) {
			root.pendingText = body;
			return true;
		}

		root.post(target, body);

		return true;
	}

	function post(sessionID, body) {
		root.sending = true;
		root.sendSession = sessionID;
		root.sendBody = body;
		sender.running = true;
	}

	// The exit code of curl decides the outcome: 0 is a delivered message,
	// anything else is a failed one.
	function finishSend(code) {
		if (!root.sending)
			return;

		const body = root.sendBody;

		root.sending = false;
		root.sendSession = "";
		root.sendBody = "";

		if (code === 0)
			root.sent(body);
		else
			root.sendError = "send failed";

		if (root.pendingText !== "") {
			const next = root.pendingText;

			root.pendingText = "";
			root.send(next);
		}
	}

	property Process sender: Process {
		command: root.sendSession === "" ? ["true"] : [
			"curl",
			"-sS",
			"-f",
			"-o",
			"/dev/null",
			"-u",
			"opencode:" + root.serverPassword,
			"-X",
			"POST",
			"-H",
			"content-type: application/json",
			"--data-binary",
			JSON.stringify({ text: root.sendBody }),
			root.serverUrl + "/api/session/" + root.sendSession + "/prompt",
		]

		onExited: function (code) {
			root.finishSend(code);
		}
	}

	property Process listSessions: Process {
		command: root.serverUrl === "" ? ["true"] : [
			"curl",
			"-sS",
			"-u",
			"opencode:" + root.serverPassword,
			root.serverUrl + "/api/session?order=desc&limit=1",
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

				if (sessions.length > 0) {
					root.touch(sessions[0].id, {
						title: sessions[0].title || "",
						directory: (sessions[0].location && sessions[0].location.directory) || "",
					}, false);
				}
			}
		}
	}

	function refreshSessions() {
		if (root.serverUrl !== "")
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
}
