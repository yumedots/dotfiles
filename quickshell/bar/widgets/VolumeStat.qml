import QtQuick
import qs.ui
import qs
import "../../tooltips"

BarStat {
	id: root

	inkId: "volume"

	readonly property var mix: Yudae.audio
	readonly property var sink: root.nodeOf(root.mix.sink)
	readonly property real volume: root.sink ? root.sink.volume : 0
	readonly property bool isMuted: root.sink ? root.sink.mute === true : false

	function nodeOf(id) {
		const list = root.mix.nodes || [];

		for (let i = 0; i < list.length; i++) {
			if (list[i].id === id)
				return list[i];
		}

		return null;
	}

	onVolumeChanged: root.pingVolume()
	onIsMutedChanged: root.pingVolume()

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
	property double bootAt: Date.now()
	property bool mixerCompact: false
	popupKeyboard: !root.osd
	popupPersistent: root.osd
	popupClosable: !root.osd
	popupPreload: true
	popupCentered: true

	function pingVolume() {
		if (Date.now() - root.bootAt < 1000)
			return;

		if (root.popupVisible && !root.osd)
			return;

		root.osd = true;

		if (!root.popupVisible)
			root.bar.openExclusive(root, false);

		osdTimer.restart();
	}

	onPopupVisibleChanged: {
		if (root.popupVisible)
			root.mixerCompact = root.osd;
		else
			root.osd = false;
	}

	Timer {
		id: osdTimer

		interval: Config.volumeOsdMs

		onTriggered: root.closePopup()
	}

	popupContent: Component {
		VolumeMixer {
			shown: root.popupVisible
			compact: root.mixerCompact
			onCloseRequested: root.closePopup()
		}
	}
}
