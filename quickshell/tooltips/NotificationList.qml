import QtQuick
import qs.ui
import qs.services
import qs

Item {
	id: root

	signal closeRequested()

	property bool single: false
	property int selected: -1
	property int detail: -1

	readonly property int count: Notifications.count
	readonly property var entries: Notifications.list
	readonly property var ordered: root.newestFirst()
	readonly property bool opened: root.detail >= 0 && root.detail < root.count
	readonly property var model: root.opened
		? [root.ordered[root.detail]]
		: (root.single ? root.ordered.slice(0, 1) : root.ordered)
	readonly property bool empty: root.count === 0
	readonly property var current: root.opened
		? root.ordered[root.detail]
		: (root.selected >= 0 && root.selected < root.count ? root.ordered[root.selected] : null)
	readonly property int viewport: root.single
		? Math.max(Config.notifyRowHeight, list.contentHeight)
		: Config.notifyVisibleRows * Config.notifyRowHeight

	focus: true

	implicitWidth: Config.notifyWidth + Config.notifyPadding * 2
	implicitHeight: Config.notifyPaddingY * 2 + root.viewport

	onCountChanged: root.clamp()
	onSelectedChanged: root.reveal()

	function newestFirst() {
		const out = [];

		for (let i = root.entries.length - 1; i >= 0; i--)
			out.push(root.entries[i]);

		return out;
	}

	function clamp() {
		if (root.selected >= root.count || root.selected < 0)
			root.selected = -1;

		if (root.detail >= root.count)
			root.detail = -1;
	}

	function move(step) {
		if (root.opened) {
			const max = Math.max(0, list.contentHeight - list.height);

			list.contentY = Util.clamp(list.contentY + step * Config.notifyRowHeight, 0, max);
			return;
		}

		if (root.single || root.count === 0)
			return;

		const from = root.selected < 0 ? (step > 0 ? 0 : root.count - 1) : root.selected + step;

		root.selected = Util.clamp(from, 0, root.count - 1);
	}

	function reveal() {
		if (root.single || root.selected < 0)
			return;

		const block = list.itemAtIndex(root.selected);

		if (!block) {
			list.positionViewAtIndex(root.selected, ListView.Contain);
			return;
		}

		list.contentY = Util.scrollIntoView(list.contentY, list.height, list.contentHeight, block.y, block.y + block.height);
	}

	function open() {
		if (root.single || root.selected < 0 || root.selected >= root.count)
			return;

		root.detail = root.selected;
		list.contentY = 0;
	}

	function back() {
		root.detail = -1;
		Qt.callLater(root.reveal);
	}

	function dismiss() {
		if (root.current !== null) {
			Notifications.dismiss(root.current);
			root.detail = -1;
			root.clamp();
		} else if (root.count > 0) {
			Notifications.dismiss(root.ordered[0]);
		}
	}

	function accept() {
		const row = root.current !== null ? root.current : (root.count > 0 ? root.ordered[0] : null);

		if (row === null)
			return;

		const actions = row.notification.actions || [];

		for (let i = 0; i < actions.length; i++) {
			if (actions[i].identifier === "default") {
				actions[i].invoke();
				break;
			}
		}

		Notifications.dismiss(row);
		root.closeRequested();
	}

	function clearAll() {
		Notifications.dismissAll();
		root.selected = -1;
	}

	Keys.onPressed: function (event) {
		Input.notifications(event, root);
	}

	ListView {
		id: list

		anchors.left: parent.left
		anchors.top: parent.top
		width: root.implicitWidth
		height: root.viewport
		clip: true
		spacing: 0
		interactive: false
		boundsBehavior: Flickable.StopAtBounds
		keyNavigationEnabled: false
		model: root.model



		delegate: Item {
			id: slot

			required property int index
			required property var modelData

			readonly property bool active: root.opened || (!root.single && slot.index === root.selected)
			readonly property real viewport: ListView.view.height
			readonly property real scroll: ListView.view.contentY
			readonly property bool cutTop: slot.y < slot.scroll - 1 && slot.y + slot.height > slot.scroll + 1
			readonly property bool cutBottom: slot.y < slot.scroll + slot.viewport - 1 && slot.y + slot.height > slot.scroll + slot.viewport + 1
			readonly property bool boxed: !root.single && !root.opened && slot.height < slot.viewport

			width: ListView.view.width
			height: root.opened ? block.implicitHeight : Math.min(block.implicitHeight, ListView.view.height)

			NotificationRow {
				id: block

				anchors.fill: parent
				entry: slot.modelData
				selected: slot.active && !root.opened
				expanded: root.opened
				expandable: !root.single
			}

			Rectangle {
				x: 0
				y: 0
				width: slot.width
				height: Config.notifySeparator
				color: Config.notifySeparatorColor
				visible: slot.boxed && slot.index === 0
			}

			Rectangle {
				x: 0
				y: slot.height - Config.notifySeparator
				width: slot.width
				height: Config.notifySeparator
				color: Config.notifySeparatorColor
				visible: slot.boxed
			}

			Rectangle {
				id: above

				anchors.right: parent.right
				y: slot.scroll - slot.y
				width: aboveLabel.width + Config.notifyPadding
				height: aboveLabel.height + Config.notifyPadding
				color: Config.surfaceTranslucent
				visible: !root.single && slot.cutTop

				Text {
					id: aboveLabel

					anchors.centerIn: parent
					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: Config.foreground
					text: Config.iconUp
				}
			}

			Rectangle {
				id: below

				anchors.right: parent.right
				y: slot.scroll + slot.viewport - slot.y - height
				width: belowLabel.width + Config.notifyPadding
				height: belowLabel.height + Config.notifyPadding
				color: Config.surfaceTranslucent
				visible: !root.single && slot.cutBottom

				Text {
					id: belowLabel

					anchors.centerIn: parent
					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: Config.foreground
					text: Config.iconDown
				}
			}
		}
	}

	Scrollbar {
		view: list
	}

	Text {
		anchors.centerIn: parent
		visible: root.empty
		font.family: Config.fontFamily
		font.pixelSize: Config.fontSize
		color: Config.muted
		text: Config.notifyEmpty
	}
}
