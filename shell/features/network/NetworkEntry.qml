import QtQuick
import qs
import qs.ui
import qs.services

Column {
	id: entry

	required property var modelData

	property string pendingSsid: ""
	property string targetSsid: ""
	property string errorText: ""
	property color errorInk: Config.foreground

	readonly property bool asking: entry.targetSsid === entry.modelData.ssid

	signal activated()
	signal submitted(string password)
	signal cancelled()

	spacing: Config.networkRowGap

	NetworkRow {
		width: parent.width
		modelData: entry.modelData
		pendingSsid: entry.pendingSsid
		targetSsid: entry.targetSsid

		onActivated: entry.activated()
	}

	SearchField {
		id: field

		width: parent.width
		visible: entry.asking
		boxColor: Config.surface
		boxHeight: Config.rowHeight
		corner: Config.rowHeight / 2
		padding: Config.rowInset
		glyph: Config.iconLock
		size: Settings.fontSize
		glyphSize: Settings.fontSize + 2
		glyphSlot: Config.rowHeight - 2 * Config.rowInset
		gap: Config.mixerListGap
		placeholder: Config.networkPasswordHint
		echoMode: TextInput.Password
		typing: entry.asking

		onTypingChanged: {
			if (!field.typing && entry.asking)
				entry.cancelled();
		}

		onKeyPressed: (event) => {
			if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
				return;

			const typed = field.text;

			field.clear();
			entry.submitted(typed);
			event.accepted = true;
		}
	}

	Text {
		width: parent.width
		visible: entry.asking && entry.errorText !== ""
		wrapMode: Text.WordWrap
		maximumLineCount: 2
		elide: Text.ElideRight
		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		color: entry.errorInk
		text: entry.errorText
	}
}
