import QtQuick
import Quickshell.Hyprland
import qs
import qs.services
import qs.ui

Row {
	id: root
	spacing: Config.workspaceSpacing
	property var bar: null

	readonly property real baselineLift: Math.ceil(Config.barThickness)
	readonly property var persistentIds: [1, 2, 3, 4]
	readonly property int highest: root.ids.length > 0 ? root.ids[root.ids.length - 1] : 0
	readonly property int pool: Math.max(root.persistentIds.length, root.highest)
	property var ids: []
	readonly property string focusedName: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.name : ""
	readonly property var versionMatch: /^v(\d+)\.(\d+)$/.exec(root.focusedName)
	readonly property int focusedVersion: root.versionMatch ? Number(root.versionMatch[2]) : 1
	readonly property int focusedSlot: root.versionMatch ? Number(root.versionMatch[1]) : (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1)
	property var rememberedVersions: ({})
	readonly property var slotVersions: {
		const versions = Object.assign({}, root.rememberedVersions);

		if (root.versionMatch)
			versions[root.focusedSlot] = root.focusedVersion;

		return versions;
	}

	property color ink: BarInk.pick(root.bar, "workspaces", Config.foreground)

	readonly property string liveState: {
		const workspaces = Hyprland.workspaces.values;
		return workspaces.map(function (w) { return w.id; }).join(",") + "|" + (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1);
	}

	function focusWorkspace(id) {
		Hyprland.dispatch(Hyprland.usingLua
			? "hl.dsp.focus({ workspace = " + id + " })"
			: "workspace " + id);
	}

	function scroll(step) {
		const count = root.ids.length;

		if (!count)
			return;

		const index = root.ids.indexOf(root.focusedSlot);

		root.focusWorkspace(root.ids[(index + step + count) % count]);
	}

	function same(next) {
		return root.ids.length === next.length && next.every(function (id, index) { return root.ids[index] === id; });
	}

	function settle() {
		const ids = root.persistentIds.concat(Hyprland.workspaces.values.filter(function (w) { return w.id > 0; }).map(function (w) { return w.id; }));
		const next = Array.from(new Set(ids)).sort(function (left, right) { return left - right; });

		if (!root.same(next))
			root.ids = next;

	}

	function rememberVersions() {
		const versions = Object.assign({}, root.rememberedVersions);

		Hyprland.workspaces.values.forEach(function (w) {
			const match = /^v(\d+)\.(\d+)$/.exec(w.name || "");

			if (match)
				versions[Number(match[1])] = Number(match[2]);
		});

		if (root.focusedName !== "")
			versions[root.focusedSlot] = root.focusedVersion;

		root.rememberedVersions = versions;
	}

	Component.onCompleted: {
		root.settle();
		root.rememberVersions();
	}

	onLiveStateChanged: {
		debounce.restart();
		root.rememberVersions();
	}

	Timer {
		id: debounce

		interval: 7

		onTriggered: root.settle()
	}

	TextMetrics {
		id: digitMetrics

		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		text: "8"
	}

	TextMetrics {
		id: sampleMetrics

		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		text: Config.valueSample
	}

	readonly property real slotWidth: digitMetrics.advanceWidth + 8

	Repeater {
		model: root.pool

		delegate: Item {
			id: ws

			required property int index

			readonly property int workspaceId: index + 1
			readonly property int version: root.slotVersions[ws.workspaceId] || 1
			readonly property bool active: root.focusedSlot === ws.workspaceId
			readonly property bool versioned: ws.version > 1
			property real reform: 0

			onVersionChanged: reformSequence.restart()

			Component.onCompleted: ws.reform = ws.versioned ? 1 : 0

			SequentialAnimation {
				id: reformSequence

				NumberAnimation {
					target: ws
					property: "reform"
					to: 0
					duration: ws.versioned ? Config.workspaceMorphMs / 3 : Config.workspaceMorphMs
					easing.type: ws.versioned ? Easing.OutCubic : Easing.OutBack
				}

				NumberAnimation {
					target: ws
					property: "reform"
					to: ws.versioned ? 1 : 0
					duration: ws.versioned ? Config.workspaceMorphMs : 0
					easing.type: Easing.OutBack
				}
			}

			visible: root.ids.indexOf(ws.workspaceId) >= 0

			readonly property bool boxed: ws.active
			readonly property bool marked: ws.boxed || ws.versioned
			readonly property color labelColor: ws.marked ? Qt.rgba(1 - root.ink.r, 1 - root.ink.g, 1 - root.ink.b, 1) : root.ink
			readonly property real figurePadX: ws.versioned ? 8 : 4
			readonly property real figurePadY: ws.versioned ? 6 : 2

			implicitWidth: Math.max(root.slotWidth, label.implicitWidth + 8)
			implicitHeight: sampleMetrics.tightBoundingRect.height

			Figures {
				id: selector

				width: label.implicitWidth + ws.figurePadX * 2
				height: sampleMetrics.tightBoundingRect.height + ws.figurePadY * 2
				version: ws.version
				morph: ws.reform
				color: root.ink
				visible: ws.marked

				x: (ws.implicitWidth - selector.width) / 2
				y: (sampleMetrics.tightBoundingRect.height - selector.height) / 2

				Behavior on exponent {
					NumberAnimation {
						duration: Config.workspaceMorphMs
						easing.type: Easing.OutCubic
					}
				}
			}

			Text {
				id: label

				anchors.centerIn: selector
				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: ws.labelColor
				text: "" + ws.workspaceId
			}

			MouseArea {
				anchors.fill: parent
				anchors.margins: -Config.barHitPadding

				onClicked: root.focusWorkspace(ws.workspaceId)
			}
		}
	}
}
