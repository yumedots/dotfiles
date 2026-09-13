import QtQuick
import Quickshell.Services.Pipewire
import "config.js" as Config

BarStat {
	id: root

	signal clicked()
	signal exited()

	readonly property var sink: Pipewire.defaultAudioSink
	readonly property real volume: root.sink && root.sink.audio ? root.sink.audio.volume : 0
	readonly property bool isMuted: root.sink && root.sink.audio ? root.sink.audio.muted : false
	readonly property alias hovered: area.containsMouse

	pct: root.volume * 100
	barColor: Config.volumeBase
	textColor: root.isMuted ? Config.muted : Config.volumeBase
	icon: root.pct >= 67 ? Config.iconVolumeHigh
		: root.pct >= 34 ? Config.iconVolumeMid
		: Config.iconVolumeLow
	value: Math.round(root.pct) + "%"

	PwObjectTracker {
		objects: [Pipewire.defaultAudioSink]
	}

	MouseArea {
		id: area

		anchors.fill: parent
		hoverEnabled: true

		onClicked: root.clicked()
		onExited: root.exited()
	}
}
