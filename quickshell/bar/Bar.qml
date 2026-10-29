import QtQuick
import Quickshell
import qs.ui
import qs
import qs.services
import "widgets"

PanelWindow {
	id: bar

	required property var modelData
	screen: modelData

	readonly property var layout: Yudae.bar && Yudae.bar.left ? Yudae.bar : barLayoutEmpty()
	property var widgets: ({})

	readonly property bool atBottom: bar.layout.position === "bottom"
	readonly property real outerMargin: Config.barFloating ? Config.gapsOut : 0
	readonly property var centerItem: bar.widgets[bar.layout.centerAnchor]
	readonly property var centerSlot: bar.centerItem && bar.centerItem.parent && bar.centerItem.parent.parent === centerRow ? bar.centerItem.parent : null

	anchors {
		top: !bar.atBottom
		bottom: bar.atBottom
		left: true
		right: true
	}

	margins {
		top: bar.atBottom ? 0 : bar.outerMargin
		bottom: bar.atBottom ? bar.outerMargin : 0
		left: bar.outerMargin
		right: bar.outerMargin
	}

	readonly property real contentHeight: Math.max(leftRow.implicitHeight, centerRow.implicitHeight, rightRow.implicitHeight)

	implicitHeight: Math.ceil(bar.contentHeight) + 2 * border.inset
	exclusiveZone: implicitHeight
	color: "transparent"

	function componentFor(id) {
		if (id === "workspaces") return workspacesComponent;
		if (id === "clock") return clockComponent;
		if (id === "weather") return weatherComponent;
		if (id === "notify") return notifyComponent;
		if (id === "github") return githubComponent;
		if (id === "tray") return trayComponent;
		if (id === "cpu") return cpuComponent;
		if (id === "memory") return memoryComponent;
		if (id === "media") return mediaComponent;
		if (id === "network") return networkComponent;
		if (id === "volume") return volumeComponent;
		if (id === "power") return powerComponent;
		if (id === "display") return displayComponent;
		if (id === "agent") return agentComponent;
		if (id === "spacer") return spacerComponent;

		return null;
	}

	function isCenterSlot(id) {
		const center = bar.layout.center;

		return center !== undefined && center !== null && center.some(function (entry) {
			return entry && entry.id === id;
		});
	}

	function register(id, item) {
		const next = Object.assign({}, bar.widgets);

		next[id] = item;
		bar.widgets = next;
	}

	function unregister(id) {
		if (bar.widgets[id] === undefined)
			return;

		const next = Object.assign({}, bar.widgets);

		delete next[id];
		bar.widgets = next;
	}

	function closePopups(except) {
		Object.keys(bar.widgets).forEach(function (id) {
			const item = bar.widgets[id];

			if (item && item !== except && item.popupPersistent !== true && typeof item.closePopup === "function")
				item.closePopup();
		});
	}

	function anyPopupOpen() {
		return Object.keys(bar.widgets).some(function (id) {
			const item = bar.widgets[id];

			return item && typeof item.isPopupOpen === "function" && item.isPopupOpen();
		});
	}

	function openExclusive(widget, keyboard) {
		const open = widget && typeof widget.isPopupOpen === "function" && widget.isPopupOpen();

		if (widget && typeof widget.wantKeyboard === "function")
			widget.wantKeyboard(keyboard === true);

		if (open) {
			bar.closePopups(null);

			return;
		}

		bar.lastOpened = widget;

		if (widget && typeof widget.openPopup === "function")
			widget.openPopup();

		Handoff.run(function () {
			bar.closePopups(bar.lastOpened);
		});
	}

	property var lastOpened: null

	function toggleWidget(id, keyboard) {
		bar.openExclusive(bar.widgets[id], keyboard);
	}

	function toggleBare() {
		BarInk.toggle(bar);
	}

	Component.onCompleted: {
		BarInk.register(bar);

		if (BarInk.wantsBare)
			BarInk.ensure(bar);
	}

	Component.onDestruction: BarInk.unregister(bar)


	readonly property point origin: Qt.point(bar.margins.left, bar.atBottom
		? (bar.screen ? bar.screen.height : 0) - bar.margins.bottom - bar.implicitHeight
		: bar.margins.top)

	function widgetAt(x, y) {
		const ids = Object.keys(bar.widgets);

		for (let i = 0; i < ids.length; i++) {
			const item = bar.widgets[ids[i]];

			if (!item.visible)
				continue;

			const at = item.mapToItem(bar.contentItem, 0, 0);

			if (x - bar.origin.x >= at.x && x - bar.origin.x <= at.x + item.width && y - bar.origin.y >= at.y && y - bar.origin.y <= at.y + item.height)
				return item;
		}

		return null;
	}

	function clickAt(x, y) {
		const item = bar.widgetAt(x, y);

		if (item && typeof item.clicked === "function") {
			bar.closePopups(item);
			item.clicked();
			return;
		}

		bar.closePopups(null);
	}

	signal widgetActivated()

	function activateWidget(widget, keyboard) {
		const open = widget && typeof widget.isPopupOpen === "function" && widget.isPopupOpen();

		if (widget && typeof widget.wantKeyboard === "function")
			widget.wantKeyboard(keyboard === true);

		bar.closePopups(widget);

		if (!widget || typeof widget.openPopup !== "function")
			return;

		if (open) {
			widget.closePopup();
			return;
		}

		bar.widgetActivated();
		widget.openPopup();
	}

	Component { id: workspacesComponent; Workspaces {} }
	Component { id: clockComponent; Clock {} }
	Component { id: weatherComponent; WeatherStat {} }
	Component { id: notifyComponent; NotifyStat {} }
	Component { id: githubComponent; ContribStat {} }
	Component { id: trayComponent; Tray {} }
	Component { id: cpuComponent; CpuStat {} }
	Component { id: memoryComponent; MemoryStat {} }
	Component { id: mediaComponent; MediaStat {} }
	Component { id: networkComponent; NetworkStat {} }
	Component { id: volumeComponent; VolumeStat {} }
	Component { id: powerComponent; PowerStat {} }
	Component { id: displayComponent; DisplayStat {} }
	Component { id: agentComponent; AgentStat {} }
	Component { id: spacerComponent; Spacer {} }

	Component {
		id: slotDelegate

		Loader {
			id: slotLoader

			required property var modelData
			required property int index

			sourceComponent: bar.componentFor(modelData.id)
			visible: !item || item.wanted === undefined ? true : item.wanted
			anchors.bottom: parent.bottom
			anchors.bottomMargin: item ? item.baselineLift : 0

			onLoaded: {
				if (item.settings !== undefined)
					item.settings = modelData;
				if (item.mode !== undefined && modelData.mode !== undefined)
					item.mode = modelData.mode;
				if (item.bar !== undefined)
					item.bar = bar;
				if (item.popupCentered !== undefined && bar.isCenterSlot(modelData.id)) {
					item.popupCentered = true;
					if (item.popupAlwaysCentered !== undefined)
						item.popupAlwaysCentered = true;
				}
				bar.register(modelData.id, item);
			}

			Component.onDestruction: bar.unregister(modelData.id)
		}
	}

	HyprBorder {
		id: border

		anchors.fill: parent
		padding: Config.barInset
		borderWidth: Config.barBorderWidth
		shadowEnabled: false
		backgroundColor: BarInk.bare ? "transparent" : Config.surfaceTranslucent

		Behavior on backgroundColor {
			ColorAnimation {
				duration: Config.barFadeMs
			}
		}
	}

	MouseArea {
		anchors.fill: parent

		onClicked: bar.closePopups(null)
		onDoubleClicked: BarInk.toggle(bar)
	}

	Row {
		id: leftRow

		anchors.left: parent.left
		anchors.leftMargin: border.inset + Config.barPadding
		anchors.bottom: parent.bottom
		anchors.bottomMargin: border.inset
		spacing: Config.spacing

		Repeater {
			model: bar.layout.left
			delegate: slotDelegate
		}
	}

	Row {
		id: centerRow

		anchors.bottom: parent.bottom
		anchors.bottomMargin: border.inset
		spacing: Config.spacing
		x: Math.round(bar.width / 2 - (bar.centerSlot ? bar.centerSlot.x + bar.centerSlot.width / 2 : centerRow.width / 2))

		Repeater {
			model: bar.layout.center
			delegate: slotDelegate
		}
	}

	Row {
		id: rightRow

		anchors.right: parent.right
		anchors.rightMargin: border.inset + Config.barPadding
		anchors.bottom: parent.bottom
		anchors.bottomMargin: border.inset
		spacing: Config.barStatSpacing

		Repeater {
			model: bar.layout.right
			delegate: slotDelegate
		}
	}

	function barLayoutEmpty() {
		return {
			position: "top",
			transparent: false,
			centerAnchor: "",
			left: [],
			center: [],
			right: []
		};
	}

}
