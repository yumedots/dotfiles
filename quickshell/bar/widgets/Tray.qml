import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.DBusMenu
import Quickshell.Services.SystemTray
import qs.ui
import qs

Row {
	id: root

	property var bar: null
	property bool expanded: false
	property Item menuAnchor: null

	readonly property var items: SystemTray.items.values ? SystemTray.items.values : []
	readonly property real baselineLift: Math.ceil(Config.barThickness)

	// ponytail: the row is one text line tall (the same box BarText draws in), so
	// icons and glyphs centre on the bar's baseline instead of floating above it.
	// Ceiling: content taller than a line overflows symmetrically, which is fine
	// here because nothing clips the row.
	readonly property real lineHeight: ink.tightBoundingRect.height

	visible: root.items.length > 0
	spacing: Config.trayIconGap

	onExpandedChanged: if (!root.expanded) root.closeMenu()

	function openMenu(item, anchor) {
		root.menuAnchor = anchor;
		menu.menu = item.menu;
		menuPopup.open();
	}

	function closeMenu() {
		menuPopup.close();
	}

	function openPopup() {
		menuPopup.open();
	}

	function closePopup() {
		menuPopup.close();
	}

	function isPopupOpen() {
		return menuPopup.shown;
	}

	function clicked() {
		root.expanded = !root.expanded;
	}

	TextMetrics {
		id: ink

		font.family: Config.fontFamily
		font.pixelSize: Config.fontSize
		text: Config.valueSample
	}

	QsMenuOpener {
		id: menu
	}

	Item {
		implicitWidth: Config.trayGroupSize
		implicitHeight: root.lineHeight

		Text {
			anchors.centerIn: parent
			font.family: Config.fontFamily
			font.pixelSize: Config.trayGroupSize
			color: Config.foreground
			text: Config.iconPrev
			rotation: root.expanded ? 180 : 0
		}

		MouseArea {
			anchors.fill: parent
			anchors.margins: -Config.barHitPadding
			onClicked: root.clicked()
		}
	}

	Repeater {
		model: root.expanded ? root.items : []

		delegate: Item {
			id: slot

			required property var modelData

			implicitWidth: Config.trayIconSize
			implicitHeight: root.lineHeight

			AppIcon {
				id: icon

				anchors.centerIn: parent
				source: slot.modelData.icon
				implicitSize: Config.trayIconSize
				visible: false
			}

			MultiEffect {
				anchors.fill: icon
				source: icon
				colorization: 1
				colorizationColor: Config.foreground
			}

			MouseArea {
				anchors.fill: parent
				anchors.margins: -Config.barHitPadding
				acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

				onClicked: function (mouse) {
					if (mouse.button === Qt.LeftButton)
						slot.modelData.activate();
					else if (mouse.button === Qt.MiddleButton)
						slot.modelData.secondaryActivate();
					else if (slot.modelData.hasMenu)
						root.openMenu(slot.modelData, slot);
					else
						slot.modelData.activate();
				}
			}
		}
	}

	// ponytail: top level entries only, no nested submenus (an entry with children
	// triggers nothing here). Add a nested opener per entry if one is ever missed.
	Tooltip {
		id: menuPopup

		anchorWindow: root.bar
		anchorItem: root.menuAnchor
		contentPadding: Config.trayMenuPadding

		Column {
			Repeater {
				model: menu.children

				delegate: Item {
					id: option

					required property var modelData

					readonly property bool separator: option.modelData.isSeparator === true
					readonly property bool enabled: option.modelData.enabled !== false

					implicitWidth: Math.max(Config.trayMenuWidth, label.implicitWidth + 2 * Config.trayMenuPadding)
					implicitHeight: option.separator ? Config.trayMenuSeparator : Config.trayMenuRowHeight
					width: implicitWidth
					height: implicitHeight

					Highlight {
						active: !option.separator && option.enabled && hit.containsMouse
					}

					Rectangle {
						anchors.verticalCenter: parent.verticalCenter
						width: parent.width
						height: Config.trayMenuSeparator
						color: Config.muted
						visible: option.separator
					}

					Text {
						id: label

						anchors.left: parent.left
						anchors.leftMargin: Config.trayMenuPadding
						anchors.right: parent.right
						anchors.rightMargin: Config.trayMenuPadding
						anchors.verticalCenter: parent.verticalCenter
						visible: !option.separator
						elide: Text.ElideRight
						font.family: Config.fontFamily
						font.pixelSize: Config.fontSize
						color: option.enabled ? Config.foreground : Config.muted
						text: option.modelData.text
					}

					MouseArea {
						id: hit

						anchors.fill: parent
						enabled: option.enabled && !option.separator
						hoverEnabled: true

						onClicked: {
							option.modelData.triggered();
							root.closeMenu();
						}
					}
				}
			}
		}
	}
}
