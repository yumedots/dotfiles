pragma Singleton

import QtQuick
import Quickshell
import qs
import qs.services

QtObject {
	id: root

	readonly property int fontSize: Yudae.settingsFontSize > 0 ? Yudae.settingsFontSize : Config.fontSize
	readonly property int iconSize: Yudae.settingsIconSize > 0 ? Yudae.settingsIconSize : Config.iconSize
	readonly property string record: Yudae.settingsRecord
	readonly property string path: Quickshell.shellDir + "/" + Config.displayFile
}
