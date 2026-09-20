import QtQuick
import Quickshell.Services.Pipewire
import qs.ui
import qs
import "../../tooltips"

BarStat {
	id: root

	property var bar: null

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

	function openPopup() {
		popup.open();
	}

	function closePopup() {
		popup.hideNow();
	}

	function isPopupOpen() {
		return popup.shown;
	}

	PwObjectTracker {
		objects: [Pipewire.defaultAudioSink]
	}

	Tooltip {
		id: popup

		anchorWindow: root.bar
		anchorItem: root
		wantsKeyboard: true

		VolumeMixer {
			onCloseRequested: popup.close()
		}
	}
}
