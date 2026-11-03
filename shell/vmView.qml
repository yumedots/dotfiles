import QtQuick
import Quickshell

ShellRoot {
	id: root

	readonly property string vm: Quickshell.env("YUDAE_VM")
	readonly property string yudae: Quickshell.env("HOME") + "/.local/bin/yudae"
	readonly property string shot: "/run/user/1000/yudae-view-" + root.vm + ".png"
	property int ticks: 0
	property bool alive: true

	function send(args) {
		if (root.vm === "")
			return;

		Quickshell.execDetached(args);
	}

	Timer {
		interval: 800
		running: root.alive
		repeat: true
		onTriggered: {
			root.ticks += 1;
			root.send([root.yudae, "vm", "screenshot", root.vm, root.shot]);
		}
	}

	FloatingWindow {
		id: window

		visible: true
		width: 1280
		height: 720
		color: "black"
		title: "VM " + root.vm

		onVisibleChanged: {
			if (visible)
				return;

			root.alive = false;
			root.send([root.yudae, "vm", "release", root.vm]);
		}

		Item {
			id: surface

			anchors.fill: parent
			focus: true

			Image {
				id: screen

				anchors.fill: parent
				fillMode: Image.PreserveAspectFit
				cache: false
				source: "file://" + root.shot + "?t=" + root.ticks
			}

			MouseArea {
				id: pointer

				anchors.fill: parent
				hoverEnabled: true
				acceptedButtons: Qt.LeftButton | Qt.RightButton

				readonly property real fit: screen.sourceSize.width > 0 ? Math.min(width / screen.sourceSize.width, height / screen.sourceSize.height) : 1
				readonly property real offX: (width - screen.sourceSize.width * fit) / 2
				readonly property real offY: (height - screen.sourceSize.height * fit) / 2

				onClicked: function (event) {
					const x = Math.round((event.x - offX) / fit);
					const y = Math.round((event.y - offY) / fit);
					root.send([root.yudae, "vm", "click", root.vm, String(x), String(y), "--human"]);
				}

				onPositionChanged: function (event) {
					if (!pressed)
						return;

					const x = Math.round((event.x - offX) / fit);
					const y = Math.round((event.y - offY) / fit);
					root.send([root.yudae, "vm", "move", root.vm, String(x), String(y), "--human"]);
				}
			}

			Keys.onPressed: function (event) {
				if (event.text !== "") {
					root.send([root.yudae, "vm", "type", root.vm, event.text, "--human"]);
					event.accepted = true;
					return;
				}

				const code = keyCode(event.key);

				if (code !== "") {
					root.send([root.yudae, "vm", "key", root.vm, code, "--human"]);
					event.accepted = true;
				}
			}

			Component.onCompleted: surface.forceActiveFocus()

			function keyCode(key) {
				if (key === Qt.Key_Return || key === Qt.Key_Enter) return "ret";
				if (key === Qt.Key_Escape) return "esc";
				if (key === Qt.Key_Backspace) return "backspace";
				if (key === Qt.Key_Tab) return "tab";
				if (key === Qt.Key_Left) return "left";
				if (key === Qt.Key_Right) return "right";
				if (key === Qt.Key_Up) return "up";
				if (key === Qt.Key_Down) return "down";
				if (key === Qt.Key_Space) return "spc";
				return "";
			}
		}
	}
}
