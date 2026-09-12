import QtQuick
import Quickshell.Services.Pipewire
import "theme.js" as Theme

BarStat {
	id: root

	readonly property var sink: Pipewire.defaultAudioSink
	readonly property real volume: root.sink && root.sink.audio ? root.sink.audio.volume : 0
	readonly property bool isMuted: root.sink && root.sink.audio ? root.sink.audio.muted : false

	pct: root.volume * 100
	barColor: Theme.volumeBase
	textColor: root.isMuted ? Theme.muted : Theme.volumeBase
	icon: root.pct >= 67 ? Theme.iconVolumeHigh
		: root.pct >= 34 ? Theme.iconVolumeMid
		: Theme.iconVolumeLow
	value: Math.round(root.pct) + "%"

	PwObjectTracker {
		objects: [Pipewire.defaultAudioSink]
	}
}
