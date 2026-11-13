import QtQuick
import qs
import qs.services
import qs.ui

AppWindow {
	id: win

	appTitle: "Disk"
	appMinWidth: 900
	appMinHeight: 560
	implicitWidth: 1280
	implicitHeight: 800

	property string tab: "map"
	property var packageRows: []
	readonly property var packageItems: win.packageRows.map(function (r) {
		return { key: r.name, name: r.name, detail: r.version + "  " + r.repo + (r.orphan ? "  orphan" : ""), size: r.size, sizeText: r.sizeText, raw: r };
	})
	readonly property var cacheItems: win.cacheRows.map(function (r) {
		return { key: r.id, name: r.label, detail: r.path, size: r.size, sizeText: r.sizeText, raw: r };
	})
	property var cacheRows: []
	property var pending: null
	property var mapSelection: ({})
	property var packageSelection: ({})
	property var cacheSelection: ({})
	readonly property int mapSelectionCount: Object.keys(win.mapSelection).length
	readonly property int packageSelectionCount: Object.keys(win.packageSelection).length
	readonly property int cacheSelectionCount: Object.keys(win.cacheSelection).length
	property int sidebarWidth: 248
	readonly property var selectedRows: {
		const tag = function (rows, group) {
			return rows.map(function (r) { return Object.assign({ group: group }, r); });
		};
		return tag(Object.values(win.mapSelection), "Files").concat(tag(Object.values(win.packageSelection), "Packages"), tag(Object.values(win.cacheSelection), "Caches"));
	}
	readonly property real selectedTotal: win.sumSizes(win.selectedRows)

	readonly property var disk: Yudae.diskState || ({})
	readonly property var view: win.disk.view || null
	readonly property var children: win.view && win.view.children ? win.view.children : []
	readonly property string focus: win.disk.focus || win.disk.root || "/"
	readonly property bool scanning: win.disk.status === "scanning"
	readonly property real usedRatio: (win.disk.deviceTotal || 0) > 0 ? Math.min(1, (win.disk.used || 0) / win.disk.deviceTotal) : 0

	function formatSize(bytes) {
		const value = Number(bytes) || 0;

		if (value >= 1024 * 1024 * 1024 * 1024)
			return (value / (1024 * 1024 * 1024 * 1024)).toFixed(1) + " TB";
		if (value >= 1024 * 1024 * 1024)
			return (value / (1024 * 1024 * 1024)).toFixed(1) + " GB";
		if (value >= 1024 * 1024)
			return (value / (1024 * 1024)).toFixed(1) + " MB";
		if (value >= 1024)
			return (value / 1024).toFixed(1) + " kB";
		return value + " B";
	}

	function rowsOf(list) {
		const out = [];

		for (let i = 0; i < list.length; i++) {
			const entry = list[i];
			out.push({
				name: entry.name || "",
				version: entry.version || "",
				size: entry.size || 0,
				sizeText: win.formatSize(entry.size || 0),
				repo: entry.repo || entry.origin || "",
				orphan: entry.orphan === true,
				flatpak: entry.repo === undefined,
			});
		}

		return out;
	}

	function scan() {
		win.mapSelection = ({});
		Yudae.diskCommand("scan", { path: win.disk.root || "/" });
	}

	function openPath(child) {
		Yudae.diskCommand("view", { path: child });
	}

	function up() {
		const focus = win.focus;
		const cut = focus.lastIndexOf("/");

		if (cut <= 0) {
			openPath("/");
			return;
		}

		openPath(focus.substring(0, cut));
	}

	function selectTab(name) {
		win.tab = name;

		if (name === "packages" && win.packageRows.length === 0)
			loadPackages();
		if (name === "caches" && win.cacheRows.length === 0)
			loadCaches();
	}

	function loadPackages() {
		Yudae.diskCommand("packages", {}, function (result) {
			if (!result)
				return;

			win.packageRows = win.rowsOf(result.list || []).concat(win.rowsOf(result.flatpak || []));
		});
	}

	function loadCaches() {
		Yudae.diskCommand("caches", {}, function (result) {
			if (!result)
				return;

			const rows = [];
			const list = result.list || [];

			for (let i = 0; i < list.length; i++) {
				const entry = list[i];
				rows.push({
					id: entry.id || "",
					label: entry.label || "",
					path: entry.path || "",
					tool: entry.tool || "",
					size: entry.size || 0,
					sizeText: win.formatSize(entry.size || 0),
					root: entry.root === true,
					exists: entry.exists === true,
				});
			}

			win.cacheRows = rows;
		});
	}

	function toggleMapItem(item) {
		const next = Object.assign({}, win.mapSelection);

		if (next[item.path])
			delete next[item.path];
		else
			next[item.path] = item;

		win.mapSelection = next;
	}

	function togglePackage(row) {
		const next = Object.assign({}, win.packageSelection);

		if (next[row.name])
			delete next[row.name];
		else
			next[row.name] = row;

		win.packageSelection = next;
	}

	function toggleCache(row) {
		const next = Object.assign({}, win.cacheSelection);

		if (next[row.id])
			delete next[row.id];
		else
			next[row.id] = row;

		win.cacheSelection = next;
	}

	function sumSizes(rows) {
		let size = 0;

		for (let i = 0; i < rows.length; i++)
			size += Number(rows[i].size) || 0;

		return size;
	}

	function unselect(row) {
		const drop = function (map, key) {
			const next = Object.assign({}, map);
			delete next[key];
			return next;
		};

		if (row.group === "Packages")
			win.packageSelection = drop(win.packageSelection, row.name);
		else if (row.group === "Caches")
			win.cacheSelection = drop(win.cacheSelection, row.id);
		else
			win.mapSelection = drop(win.mapSelection, row.path);
	}

	function cleanCurrent() {
		const files = Object.values(win.mapSelection);
		const pkgs = Object.values(win.packageSelection);
		const caches = Object.values(win.cacheSelection);

		if (files.length + pkgs.length + caches.length === 0)
			return;

		win.pending = {
			kind: "clean-all",
			items: files,
			names: pkgs.map(function (r) { return r.name; }),
			ids: caches.map(function (r) { return r.id; }),
			count: files.length + pkgs.length + caches.length,
			label: (files.length + pkgs.length + caches.length) + " items",
			size: win.selectedTotal
		};
	}

	function cleanFileAt(items, index) {
		if (index >= items.length) {
			win.mapSelection = ({});
			Yudae.diskCommand("view", { path: win.focus });
			return;
		}

		Yudae.diskCommand("delete", { path: items[index].path }, function () {
			win.cleanFileAt(items, index + 1);
		});
	}

	function cleanCacheAt(ids, index) {
		if (index >= ids.length) {
			win.cacheSelection = ({});
			win.loadCaches();
			return;
		}

		Yudae.diskCommand("clean", { id: ids[index], confirm: true }, function () {
			win.cleanCacheAt(ids, index + 1);
		});
	}

	function confirmPending() {
		if (!win.pending)
			return;

		const action = win.pending;
		win.pending = null;

		if (action.names.length > 0) {
			Yudae.diskCommand("uninstall", { names: action.names, confirm: true }, function () {
				win.packageSelection = ({});
				win.loadPackages();
			});
		}

		if (action.ids.length > 0)
			win.cleanCacheAt(action.ids, 0);

		if (action.items.length > 0)
			win.cleanFileAt(action.items, 0);
	}

	Rectangle {
		anchors.fill: parent
		color: Config.surface
	}

	Column {
		anchors.fill: parent
		spacing: 0

		Row {
			width: parent.width
			height: parent.height

		Item {
			width: win.sidebarWidth
			height: parent.height
		}

		Item {
			width: parent.width - win.sidebarWidth
			height: parent.height

			Column {
				anchors.fill: parent
				anchors.margins: 22
				visible: win.tab === "map"
				spacing: 12

				Item {
					width: parent.width
					height: 20

					Item {
						id: upButton

						anchors.left: parent.left
						anchors.verticalCenter: parent.verticalCenter
						width: 20
						height: 20
						opacity: win.focus === (win.disk.root || "/") ? 0.3 : (upMouse.containsMouse ? 1 : 0.7)

						Glyph {
							anchors.centerIn: parent
							glyph: "\uf062"
							size: 13
							color: Config.foreground
						}

						MouseArea {
							id: upMouse

							anchors.fill: parent
							hoverEnabled: true
							onClicked: win.up()
						}
					}

					Text {
						anchors.left: upButton.right
						anchors.leftMargin: 10
						anchors.right: usage.left
						anchors.rightMargin: 12
						anchors.verticalCenter: parent.verticalCenter
						elide: Text.ElideMiddle

						font.family: Config.fontFamily
						font.pixelSize: 12
						color: Config.foreground
						text: win.focus
					}

					Column {
						id: usage

						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
						width: 200
						height: 20
						spacing: 4

						Rectangle {
							width: parent.width
							height: 3
							color: Config.dim

							Rectangle {
								width: parent.width * win.usedRatio
								height: parent.height
								color: Config.memoryBase
							}
						}

						Text {
							width: parent.width

							font.family: Config.fontFamily
							font.pixelSize: 10
							color: Config.dim
							horizontalAlignment: Text.AlignRight
							text: win.formatSize(win.disk.used || 0) + " used  " + win.formatSize(win.disk.free || 0) + " free"
						}
					}
				}

				Item {
					width: parent.width
					height: parent.height - 20 - 12 - (win.pending ? 40 : 0)
					clip: true

					Bubbles {
						anchors.fill: parent
						items: win.children
						selected: win.mapSelection
						onToggled: function (item) { win.toggleMapItem(item); }
						onActivated: function (item) {
							if (item.kind === "dir")
								win.openPath(item.path);
						}
					}

					Text {
						anchors.centerIn: parent

						font.family: Config.fontFamily
						font.pixelSize: 13
						color: Config.dim
						text: win.scanning ? "Scanning" : (win.view ? "No children" : "Scan to build the map")
						visible: win.children.length === 0
					}
				}

			}

			Item {
				anchors.fill: parent
				visible: win.tab === "packages"

				RowList {
					anchors.fill: parent
					anchors.margins: 22
					anchors.bottomMargin: win.pending ? 62 : 22
					rows: win.packageItems
					glyph: Config.diskIconPackage
					selected: win.packageSelection
					onToggled: function (row) { win.togglePackage(row.raw); }
				}

				Text {
					anchors.centerIn: parent

					font.family: Config.fontFamily
					font.pixelSize: 13
					color: Config.dim
					text: "Load packages"
					visible: win.packageRows.length === 0

					MouseArea {
						anchors.fill: parent
						anchors.margins: -10
						onClicked: win.loadPackages()
					}
				}
			}

			Item {
				anchors.fill: parent
				visible: win.tab === "caches"

				RowList {
					anchors.fill: parent
					anchors.margins: 22
					anchors.bottomMargin: win.pending ? 62 : 22
					rows: win.cacheItems
					glyph: Config.diskIconCache
					selected: win.cacheSelection
					onToggled: function (row) { win.toggleCache(row.raw); }
				}

				Text {
					anchors.centerIn: parent

					font.family: Config.fontFamily
					font.pixelSize: 13
					color: Config.dim
					text: "Load caches"
					visible: win.cacheRows.length === 0

					MouseArea {
						anchors.fill: parent
						anchors.margins: -10
						onClicked: win.loadCaches()
					}
				}
			}

		}
		}
	}

	Item {
		id: header

		x: 0
		y: 0
		width: win.sidebarWidth
		height: 84
		z: 3

		Text {
			id: titleText

			anchors.left: parent.left
			anchors.leftMargin: 14
			anchors.top: parent.top
			anchors.topMargin: 14

			font.family: Config.fontFamily
			font.pixelSize: 21
			font.weight: Font.DemiBold
			color: Config.foreground
			text: "Disk"
		}

		Rectangle {
			anchors.right: parent.right
			anchors.rightMargin: 14
			anchors.verticalCenter: titleText.verticalCenter
			width: scanLabel.width + 22
			height: 26
			color: scanMouse.containsMouse ? Config.launcherHighlight : Config.launcherSearchBox

			Text {
				id: scanLabel

				anchors.centerIn: parent

				font.family: Config.fontFamily
				font.pixelSize: 12
				color: Config.foreground
				text: "Scan"
			}

			MouseArea {
				id: scanMouse

				anchors.fill: parent
				hoverEnabled: true
				onClicked: win.scan()
			}
		}

		Row {
			anchors.left: parent.left
			anchors.leftMargin: 14
			anchors.top: titleText.bottom
			anchors.topMargin: 14
			spacing: 18

			Repeater {
				model: [["Map", "map"], ["Packages", "packages"], ["Caches", "caches"]]

				delegate: Item {
					required property var modelData

					width: tabText.width
					height: 20

					Text {
						id: tabText

						anchors.centerIn: parent

						font.family: Config.fontFamily
						font.pixelSize: 12
						color: win.tab === parent.modelData[1] ? Config.foreground : Config.dim
						text: parent.modelData[0]
					}

					MouseArea {
						anchors.fill: parent
						hoverEnabled: true
						onClicked: win.selectTab(parent.modelData[1])
					}
				}
			}
		}
	}

	Rectangle {
		anchors.left: parent.left
		anchors.leftMargin: win.sidebarWidth
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		height: 40
		z: 4
		visible: win.pending !== null
		color: Config.launcherSearchBox

		Text {
			anchors.left: parent.left
			anchors.leftMargin: 22
			anchors.right: answers.left
			anchors.rightMargin: 16
			anchors.verticalCenter: parent.verticalCenter
			elide: Text.ElideRight

			font.family: Config.fontFamily
			font.pixelSize: 12
			color: Config.foreground
			text: win.pending ? ("Are you sure you want to delete " + (win.pending.count === 1 ? "this item" : "these " + win.pending.count + " items") + "?") : ""
		}

		Row {
			id: answers

			anchors.right: parent.right
			anchors.rightMargin: 22
			anchors.verticalCenter: parent.verticalCenter
			spacing: 18

			Text {
				font.family: Config.fontFamily
				font.pixelSize: 12
				font.weight: Font.DemiBold
				color: yesMouse.containsMouse ? Config.red : Config.yellow
				text: "Yes"

				MouseArea {
					id: yesMouse

					anchors.fill: parent
					anchors.margins: -6
					hoverEnabled: true
					onClicked: win.confirmPending()
				}
			}

			Text {
				font.family: Config.fontFamily
				font.pixelSize: 12
				color: noMouse.containsMouse ? Config.foreground : Config.dim
				text: "No"

				MouseArea {
					id: noMouse

					anchors.fill: parent
					anchors.margins: -6
					hoverEnabled: true
					onClicked: win.pending = null
				}
			}
		}
	}

	SelectionSidebar {
		anchors.top: parent.top
		anchors.left: parent.left
		anchors.bottom: parent.bottom
		topInset: header.height
		width: win.sidebarWidth
		rows: win.selectedRows
		total: win.selectedTotal
		canClean: win.selectedRows.length > 0
		onClean: win.cleanCurrent()
		onUnselect: function (row) { win.unselect(row); }
	}

	MouseArea {
		x: win.sidebarWidth - 4
		anchors.top: parent.top
		anchors.bottom: parent.bottom
		width: 8
		cursorShape: Qt.SizeHorCursor
		acceptedButtons: Qt.LeftButton
		onPositionChanged: function (mouse) {
			if (pressed)
				win.sidebarWidth = Math.round(Math.max(180, Math.min(480, win.sidebarWidth + mouse.x - 4)));
		}
	}
}
