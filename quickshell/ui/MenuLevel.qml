import QtQuick
import Quickshell
import Quickshell.DBusMenu
import qs

Column {
	id: root

	property var entries: null
	property var dismiss: null
	property int openIndex: -1
	property real indent: 0
	property var levelComponent: null

	Component.onCompleted: {
		if (root.levelComponent === null)
			root.levelComponent = Qt.createComponent(Qt.resolvedUrl("MenuLevel.qml"));
	}

	spacing: 0

	Repeater {
		model: root.entries

		delegate: Column {
			id: row

			required property var modelData
			required property int index

			readonly property var entry: modelData
			readonly property bool submenu: modelData.hasChildren === true
			readonly property bool separator: modelData.isSeparator === true
			readonly property bool checked: !row.separator && modelData.checkState === 2

			spacing: 0

			QsMenuOpener {
				id: rowMenu

				menu: row.submenu && !row.separator ? row.entry : null
			}

			Item {
				id: rowItem

				readonly property bool rowEnabled: row.entry.enabled === true

				visible: true
				implicitWidth: Math.max(Config.trayMenuWidth, (rowIcon.visible ? 18 : 0) + rowLabel.implicitWidth + (rowMark.visible ? rowMark.implicitWidth + 4 : 0) + 2 * Config.trayMenuPadding + root.indent)
				implicitHeight: row.separator ? Config.trayMenuSeparator : Config.trayMenuRowHeight

				Rectangle {
					visible: row.separator
					anchors.fill: parent
					color: Config.muted
				}

				Highlight {
					visible: !row.separator
					active: hit.containsMouse && rowItem.rowEnabled
				}

				Image {
					id: rowIcon

					visible: !row.separator && rowItem.rowEnabled && row.entry.icon !== undefined && row.entry.icon !== ""
					anchors.left: parent.left
					anchors.leftMargin: Config.trayMenuPadding + root.indent
					anchors.verticalCenter: parent.verticalCenter
					width: 14
					height: 14
					source: visible ? row.entry.icon : ""
					sourceSize.width: 14
					sourceSize.height: 14
				}

				Text {
					id: rowLabel

					visible: !row.separator
					anchors.left: parent.left
					anchors.leftMargin: Config.trayMenuPadding + root.indent + (rowIcon.visible ? 18 : 0)
					anchors.right: rowMark.left
					anchors.rightMargin: rowMark.visible ? 4 : 0
					anchors.verticalCenter: parent.verticalCenter
					elide: Text.ElideRight
					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: !rowItem.rowEnabled ? Config.muted : (hit.containsMouse ? Config.launcherHighlightText : Config.foreground)
					text: row.entry.text
				}

				Text {
					id: rowMark

					visible: !row.separator && (row.submenu || row.checked)
					anchors.right: parent.right
					anchors.rightMargin: Config.trayMenuPadding
					anchors.verticalCenter: parent.verticalCenter
					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: rowItem.rowEnabled ? (hit.containsMouse ? Config.launcherHighlightText : Config.foreground) : Config.muted
					text: row.submenu ? "›" : "✓"
				}

				MouseArea {
					id: hit

					visible: !row.separator
					anchors.fill: parent
					hoverEnabled: true

					onEntered: {
						if (rowItem.rowEnabled)
							root.openIndex = row.submenu ? row.index : -1;
					}

					onClicked: {
						if (!rowItem.rowEnabled)
							return;

						if (row.submenu) {
							root.openIndex = root.openIndex === row.index ? -1 : row.index;
							return;
						}

						row.entry.triggered();

						if (root.dismiss)
							root.dismiss();
					}
				}
			}

			Loader {
				id: subLoader

				active: row.submenu && row.entry.isSeparator !== true && row.entry.enabled === true && root.openIndex === row.index
				sourceComponent: root.levelComponent

				onLoaded: {
					item.entries = rowMenu.children;
					item.dismiss = root.dismiss;
					item.indent = root.indent + 14;
					item.levelComponent = root.levelComponent;
				}
			}
		}
	}
}
