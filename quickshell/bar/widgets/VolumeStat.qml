import QtQuick
import qs.ui
import qs
import qs.services
import "../../tooltips"

BarStat {
	id: root

	inkId: "volume"

	readonly property real volume: {
		const audio = Yudae.audio;
		const list = audio.nodes || [];

		for (let i = 0; i < list.length; i++) {
			if (list[i].id === audio.sink)
				return list[i].volume;
		}

		return 0;
	}

	readonly property bool isMuted: {
		const audio = Yudae.audio;
		const list = audio.nodes || [];

		for (let i = 0; i < list.length; i++) {
			if (list[i].id === audio.sink)
				return list[i].mute === true;
		}

		return false;
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
