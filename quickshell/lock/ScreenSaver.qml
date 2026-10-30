import QtQuick
import qs
import qs.services

Item {
	id: root

	property string name: "none"

	readonly property var sources: ({ rain: "saver/Rain.qml", embers: "saver/Embers.qml" })
	readonly property string target: root.sources[root.name] !== undefined ? root.sources[root.name] : ""

	property bool front: true

	Loader {
		id: first

		anchors.fill: parent
		opacity: root.front ? 1 : 0

		Behavior on opacity {
			NumberAnimation { duration: Config.lockSaverFadeMs; easing.type: Easing.InOutSine }
		}
	}

	Loader {
		id: second

		anchors.fill: parent
		opacity: root.front ? 0 : 1

		Behavior on opacity {
			NumberAnimation { duration: Config.lockSaverFadeMs; easing.type: Easing.InOutSine }
		}
	}

	onTargetChanged: {
		const next = root.front ? second : first;

		next.source = root.target;
		root.front = !root.front;
	}
}
