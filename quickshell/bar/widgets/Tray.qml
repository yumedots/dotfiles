import QtQuick
import QtQuick.Effects
import Quickshell
import qs.ui
import qs
import qs.services

Row {
	id: root

	property var bar: null
	property bool expanded: false
	property Item menuAnchor: null
	property string menuKey: ""

	readonly property var items: Yudae.tray || []
	readonly property var menuEntries: {
		for (let i = 0; i < root.items.length; i++) {
			if (root.items[i].key === root.menuKey)
				return root.items[i].menu || [];
		}

		return [];
	}
	readonly property real baselineLift: Math.ceil(Config.barThickness)

	// The bar gives every widget a slot whether it has anything to show or
	// not, so a widget that is empty says so and the slot is taken away.
	readonly property bool wanted: root.items.length > 0

	readonly property real lineHeight: ink.tightBoundingRect.height

	visible: root.items.length > 0
	spacing: Config.trayIconGap

	onExpandedChanged: if (!root.expanded) root.closeMenu()

	function openMenu(item, anchor) {
		root.menuAnchor = anchor;
		root.menuKey = item.key;
		Yudae.cmd("tray", { key: item.key, open: true });
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
		font.pixelSize: Settings.fontSize
		text: Config.valueSample
	}

	Item {
		implicitWidth: Config.trayGroupSize
		implicitHeight: root.lineHeight

		Text {
			anchors.centerIn: parent
			font.family: Config.fontFamily
			font.pixelSize: Settings.iconSize + Config.trayChevronBoost
			color: BarInk.pick(root.bar, "tray", Config.foreground)
			text: Config.iconChevron
			rotation: root.expanded ? 180 : 0

			Behavior on color {
				enabled: BarInk.fading
				ColorAnimation {
					duration: BarInk.fadeMs
				}
			}
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

			readonly property string iconSource: {
				const url = String(slot.modelData.icon || "");
				const name = url.replace("image://icon/", "").split("?")[0];

				if (url.indexOf("image://icon/") === 0 && Quickshell.hasThemeIcon(name))
					return url;

				return AppIcons.iconOf(slot.modelData.id, [slot.modelData.title]) || url;
			}

			implicitWidth: Config.trayIconSize
			implicitHeight: root.lineHeight

			AppIcon {
				id: icon

				anchors.centerIn: parent
				source: slot.iconSource
				implicitSize: Config.trayIconSize
				visible: false
			}

			MultiEffect {
				anchors.fill: icon
				source: icon
				colorization: 1
				colorizationColor: BarInk.pick(root.bar, "tray", Config.foreground)

				Behavior on colorizationColor {
					enabled: BarInk.fading
					ColorAnimation {
						duration: BarInk.fadeMs
					}
				}
			}

			MouseArea {
				anchors.fill: parent
				anchors.margins: -Config.barHitPadding
				acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

				onClicked: function (mouse) {
					if (mouse.button === Qt.LeftButton && slot.modelData.itemIsMenu && slot.modelData.hasMenu)
						root.openMenu(slot.modelData, slot);
					else if (mouse.button === Qt.LeftButton)
						Yudae.cmd("tray", { key: slot.modelData.key, activate: 0 });
					else if (mouse.button === Qt.MiddleButton)
						Yudae.cmd("tray", { key: slot.modelData.key, activate: 1 });
					else if (slot.modelData.hasMenu)
						root.openMenu(slot.modelData, slot);
					else
						Yudae.cmd("tray", { key: slot.modelData.key, activate: 0 });
				}
			}
		}
	}

	Tooltip {
		id: menuPopup

		anchorWindow: root.bar
		anchorItem: root.menuAnchor
		contentPadding: Config.trayMenuPadding
		wantsKeyboard: true
		closable: false

		MenuLevel {
			entries: root.menuEntries
			trayKey: root.menuKey
			dismiss: function () { menuPopup.close(); }
		}
	}
}
