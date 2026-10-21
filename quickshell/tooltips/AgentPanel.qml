import QtQuick
import qs
import qs.services
import qs.ui

// The agent panel: the face at full size, the state of the agent, and an input
// line to send it a message.
//
// The field takes focus as soon as the panel opens, so a message can be typed
// straight away.
Item {
	id: root

	property var source: null

	// The session the panel sends to.
	//
	// The panel locks onto a session when it opens, so a message never slips
	// into another session while it is being written. The server sends its list
	// of sessions a moment after the shell starts, so the lock waits for a
	// session to turn up instead of settling on nothing.
	//
	// A session the user picks in the list wins over the lock.
	property string injectedTarget: ""
	property string chosenTarget: ""
	property string lockedTarget: ""

	readonly property string target: root.chosenTarget !== ""
		? root.chosenTarget
		: (root.lockedTarget !== "" ? root.lockedTarget : OpenCode.targetSession)

	signal closeRequested()

	readonly property string state: OpenCode.state
	readonly property string stateText: root.state === "working"
		? Config.agentWorkingText
		: root.state === "blocked"
			? Config.agentBlockedText
			: root.state === "error"
				? Config.agentErrorText
				: Config.agentIdleText

	// The face sits in the popup's own window, which covers the screen, so the
	// pointer is tracked against the panel's position on that screen.
	readonly property point faceCenter: {
		const win = root.Window.window;

		if (!win)
			return Qt.point(0, 0);

		const at = root.mapToItem(win.contentItem, 0, 0);
		const screen = root.source && root.source.bar ? root.source.bar.screen : null;
		const originX = screen ? screen.x : 0;
		const originY = screen ? screen.y : 0;

		return Qt.point(originX + at.x + root.width / 2, originY + at.y);
	}

	readonly property real gazeX: {
		if (!Cursor.valid)
			return 0;

		return Util.clamp((Cursor.x - root.faceCenter.x) / Config.agentFaceSize, -1, 1);
	}

	readonly property real gazeY: {
		if (!Cursor.valid)
			return 0;

		return Util.clamp((Cursor.y - root.faceCenter.y) / Config.agentFaceSize, -1, 1);
	}

	implicitWidth: Config.agentPanelWidth + 2 * Config.agentPanelPadding
	implicitHeight: column.implicitHeight + Config.agentPanelPadding * 2

	// The width of the content, which follows the panel when the panel is
	// given one, so a window around it can be resized.
	readonly property real contentWidth: root.width > 0
		? Math.max(Config.agentPanelWidth, root.width - 2 * Config.agentPanelPadding)
		: Config.agentPanelWidth

	// The height of the content, which a window around the panel takes for
	// its own height.
	readonly property real contentHeight: column.implicitHeight

	// The field takes the focus, so keystrokes land in it. The popup focuses its
	// first content item when it opens, which would take the focus back, so the
	// field claims it again until it holds.
	Component.onCompleted: {
		root.lockTarget();

		Qt.callLater(field.startTyping);

		focusTimer.restart();
	}

	// The lock takes the session the panel was opened for. When the panel is
	// given one, that one is used.
	function lockTarget() {
		if (root.injectedTarget !== "") {
			root.lockedTarget = root.injectedTarget;
			return;
		}

		if (root.lockedTarget === "")
			root.lockedTarget = OpenCode.targetSession;
	}

	// The server sends its sessions a moment after the shell starts, so the
	// lock waits for one to turn up.
	Connections {
		target: OpenCode

		function onTargetSessionChanged() {
			root.lockTarget();
		}
	}

	Timer {
		id: focusTimer

		interval: 30
		repeat: true
		running: false

		onTriggered: {
			if (field.focused) {
				focusTimer.stop();
				return;
			}

			if (!field.typing)
				field.startTyping();

			field.focusInput();
		}
	}

	function send() {
		OpenCode.send(field.text, root.target);
	}

	// The field is only cleared once the server took the message, so a failed
	// send keeps the text.
	Connections {
		target: OpenCode

		function onSent(text) {
			if (String(field.text || "").trim() === text)
				field.clear();
		}
	}

	Column {
		id: column

		x: Config.agentPanelPadding
		y: Config.agentPanelPadding
		width: root.contentWidth
		spacing: Config.agentPanelPadding

		Item {
			width: column.width
			height: Config.agentFaceSize

			// A Column positions its children, so the face is placed by x
			// rather than by an anchor, which a Column would ignore.
			AgentFace {
				id: face

				x: (parent.width - width) / 2
				y: 0
				width: Config.agentFaceSize
				height: Config.agentFaceSize

				size: Config.agentFaceSize
				state: root.state
				followCursor: true
				gazeX: root.gazeX
				gazeY: root.gazeY

				bodyColor: Config.foreground
				eyeColor: Config.surface
			}
		}

		Column {
			width: column.width
			spacing: 2

			Text {
				width: parent.width
				elide: Text.ElideRight

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.foreground
				text: Config.agentPanelTitle
			}

			Text {
				width: parent.width
				elide: Text.ElideRight

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: root.state === "error" ? Config.red : Config.muted
				text: root.stateText
			}

			Text {
				width: parent.width
				visible: text !== ""
				elide: Text.ElideRight

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.muted
				text: OpenCode.detailText
			}

			Text {
				width: parent.width
				visible: text !== ""
				elide: Text.ElideRight

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.muted
				text: OpenCode.titleOf(root.target)
			}

			Text {
				width: column.width
				visible: text !== ""
				elide: Text.ElideRight

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.red
				text: OpenCode.sendError
			}

			Text {
				width: column.width
				visible: !OpenCode.connected

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.red
				text: "OpenCode offline"
			}
		}

		// The sessions, with the ones that have work in them first.
		AgentSessions {
			id: sessions

			width: column.width

			active: OpenCode.activeSessions
			inactive: OpenCode.inactiveSessions
			target: root.target
			modelName: OpenCode.modelName(root.target)
			models: OpenCode.serverModels
			modelError: OpenCode.modelError

			onSessionChosen: function (id) {
				root.chosenTarget = id;
			}

			onModelChosen: function (id, model) {
				OpenCode.setModel(id, model);
			}
		}

		SearchField {
			id: field

			width: column.width
			boxHeight: Config.agentInputHeight

			glyph: Config.agentInputGlyph
			hintKey: ""
			size: Settings.fontSize
			boxColor: Config.launcherHighlight

			onAccepted: root.send()

			onKeyPressed: function (event) {
				// The input's key handler runs before its own accept, so the
				// send is triggered here rather than on accepted.
				if (Input.accept(event)) {
					root.send();
					event.accepted = true;
					return;
				}

				// Only the escape key is handled here. Anything else is left
				// alone so the input keeps receiving it.
				if (Input.cancel(event)) {
					field.typing = false;
					field.clear();
					root.closeRequested();
					event.accepted = true;
				}
			}
		}
	}

	Keys.onPressed: function (event) {
		// The field holds the focus, so this only runs when it does not.
		if (Input.cancel(event)) {
			field.typing = false;
			field.clear();
			root.closeRequested();
			event.accepted = true;
			return;
		}

		if (!field.typing) {
			field.startTyping();
			event.accepted = true;
		}
	}
}
