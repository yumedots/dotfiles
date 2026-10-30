import QtQuick
import qs
import qs.services

Item {
	id: root

	property string name: "none"
	property real strength: 1
	property bool running: true

	readonly property var sources: ({ drift: "saver/Drift.qml", rain: "saver/Rain.qml", embers: "saver/Embers.qml", stars: "saver/Stars.qml", pipes: "saver/Pipes.qml", mystify: "saver/Mystify.qml" })
	readonly property string target: root.sources[root.name] !== undefined ? root.sources[root.name] : ""

	property bool front: true

	Loader {
		id: first

		anchors.fill: parent
		active: root.running
		opacity: root.front ? 1 : 0

		onLoaded: if (item) item.strength = root.strength

		Behavior on opacity {
			NumberAnimation { duration: Config.lockSaverFadeMs; easing.type: Easing.InOutSine }
		}
	}

	Loader {
		id: second

		anchors.fill: parent
		active: root.running
		opacity: root.front ? 0 : 1

		onLoaded: if (item) item.strength = root.strength

		Behavior on opacity {
			NumberAnimation { duration: Config.lockSaverFadeMs; easing.type: Easing.InOutSine }
		}
	}

	onStrengthChanged: {
		if (first.item) first.item.strength = root.strength;
		if (second.item) second.item.strength = root.strength;
	}

	onTargetChanged: {
		const next = root.front ? second : first;

		next.source = root.target;
		root.front = !root.front;
	}
}
