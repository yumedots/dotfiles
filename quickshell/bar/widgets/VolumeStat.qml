import QtQuick
import Quickshell.Services.Pipewire
import qs.ui
import qs
import "../../tooltips"

BarStat {
	id: root

	readonly property var sink: Pipewire.defaultAudioSink
	readonly property real volume: root.sink && root.sink.audio ? root.sink.audio.volume : 0
	readonly property bool isMuted: root.sink && root.sink.audio ? root.sink.audio.muted : false

	pct: root.volume * 100
	barColor: Config.volumeBase
	textColor: Config.volumeBase
	dim: root.isMuted
	dimColor: Config.muted
	icon: root.pct >= 67 ? Config.iconVolumeHigh
		: root.pct >= 34 ? Config.iconVolumeMid
		: Config.iconVolumeLow
	value: Math.round(root.pct) + "%"

	property bool osd: false
	popupKeyboard: !root.osd

	function pingVolume() {
		if (root.popupVisible && !root.osd)
			return;

		root.osd = true;

		if (!root.popupVisible)
			root.bar.openExclusive(root, false);

		osdTimer.restart();
	}

	onPopupVisibleChanged: if (!root.popupVisible)
		root.osd = false

	Connections {
		target: root.sink ? root.sink.audio : null

		function onVolumeChanged() {
			root.pingVolume();
		}

		function onMutedChanged() {
			root.pingVolume();
		}
	}

	Timer {
		id: osdTimer

		interval: Config.volumeOsdMs

		onTriggered: root.closePopup()
	}

	PwObjectTracker {
		objects: [Pipewire.defaultAudioSink]
	}

	popupContent: Component {
		VolumeMixer {
			shown: root.popupVisible
			compact: root.osd || !root.popupVisible
			onCloseRequested: root.closePopup()
		}
	}
}
