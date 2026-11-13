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
	property var cacheRows: []
	property var pending: null
	property var mapSelection: ({})
	property var packageSelection: ({})
	property var cacheSelection: ({})
	readonly property int mapSelectionCount: Object.keys(win.mapSelection).length
	readonly property int packageSelectionCount: Object.keys(win.packageSelection).length
	readonly property int cacheSelectionCount: Object.keys(win.cacheSelection).length

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
		win.mapSelection = ({});
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

	function askCleanFiles() {
		const items = Object.values(win.mapSelection);

		if (items.length === 0)
			return;

		win.pending = { kind: "clean-files", items: items, label: items.length + " files", size: win.sumSizes(items) };
	}

	function askCleanPackages() {
		const rows = Object.values(win.packageSelection);

		if (rows.length === 0)
			return;

		const names = [];
		for (let i = 0; i < rows.length; i++)
			names.push(rows[i].name);

		win.pending = { kind: "uninstall", names: names, label: rows.length + " packages", size: win.sumSizes(rows) };
	}

	function askCleanCaches() {
		const rows = Object.values(win.cacheSelection);

		if (rows.length === 0)
			return;

		const ids = [];
		for (let i = 0; i < rows.length; i++)
			ids.push(rows[i].id);

		win.pending = { kind: "clean-caches", ids: ids, label: rows.length + " caches", size: win.sumSizes(rows) };
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

		if (action.kind === "clean-files") {
			win.cleanFileAt(action.items, 0);
			return;
		}

		if (action.kind === "uninstall") {
			Yudae.diskCommand("uninstall", { names: action.names, confirm: true }, function () {
				win.packageSelection = ({});
				win.loadPackages();
			});
			return;
		}

		if (action.kind === "clean-caches") {
			win.cleanCacheAt(action.ids, 0);
		}
	}

	Rectangle {
		anchors.fill: parent
		color: Config.surface
	}

	Column {
		anchors.fill: parent
		spacing: 0

		Item {
			id: header

			width: parent.width
			height: 58

			Row {
				anchors.left: parent.left
				anchors.leftMargin: 22
				anchors.verticalCenter: parent.verticalCenter
				spacing: 18

				Text {
					anchors.verticalCenter: parent.verticalCenter

					font.family: Config.fontFamily
					font.pixelSize: 21
					font.weight: Font.DemiBold
					color: Config.foreground
					text: "Disk"
				}

				Row {
					anchors.verticalCenter: parent.verticalCenter
					spacing: 20

					Repeater {
						model: [["Map", "map"], ["Packages", "packages"], ["Caches", "caches"]]

						delegate: Item {
							required property var modelData

							width: tabText.width
							height: 30

							Text {
								id: tabText

								anchors.centerIn: parent

								font.family: Config.fontFamily
								font.pixelSize: 12
								color: win.tab === modelData[1] ? Config.foreground : Config.dim
								text: modelData[0]
							}

							Rectangle {
								anchors.left: parent.left
								anchors.right: parent.right
								anchors.bottom: parent.bottom
								height: 1
								color: win.tab === modelData[1] ? Config.foreground : "transparent"
							}

							MouseArea {
								anchors.fill: parent
								hoverEnabled: true
								onClicked: win.selectTab(modelData[1])
							}
						}
					}
				}
			}

			Row {
				anchors.right: parent.right
				anchors.rightMargin: 22
				anchors.verticalCenter: parent.verticalCenter
				spacing: 10

				Text {
					anchors.verticalCenter: parent.verticalCenter

					font.family: Config.fontFamily
					font.pixelSize: 11
					color: win.disk.error && win.disk.error.length > 0 ? Config.red : Config.dim
					text: win.disk.error && win.disk.error.length > 0
						? win.disk.error
						: (win.scanning ? "Scanning" : win.formatSize(win.disk.total || 0) + " scanned")
				}

				Rectangle {
					width: scanLabel.width + 22
					height: 28
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
			}

			Rectangle {
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.bottom: parent.bottom
				height: 1
				color: Config.dim
			}
		}

		Item {
			width: parent.width
			height: parent.height - header.height

			Column {
				anchors.fill: parent
				anchors.margins: 22
				visible: win.tab === "map"
				spacing: 12

				Row {
					width: parent.width
					height: 26
					spacing: 12

					Item {
						width: 34
						height: 26

						Text {
							anchors.centerIn: parent

							font.family: Config.fontFamily
							font.pixelSize: 13
							color: upMouse.containsMouse ? Config.foreground : Config.dim
							text: "\uf062"
						}

						MouseArea {
							id: upMouse

							anchors.fill: parent
							hoverEnabled: true
							onClicked: win.up()
						}
					}

					Text {
						width: parent.width - parent.spacing - 34 - usage.width - fileActions.width - (fileActions.visible ? parent.spacing : 0)
						height: 26
						verticalAlignment: Text.AlignVCenter
						elide: Text.ElideMiddle

						font.family: Config.fontFamily
						font.pixelSize: 12
						color: Config.foreground
						text: win.focus
					}

						Row {
							id: fileActions

							height: 26
							visible: win.mapSelectionCount > 0

							Text {
								height: 26
								verticalAlignment: Text.AlignVCenter

								font.family: Config.fontFamily
								font.pixelSize: 11
								color: cleanFilesMouse.containsMouse ? Config.red : Config.dim
								text: "Clean"

								MouseArea {
									id: cleanFilesMouse

									anchors.fill: parent
									anchors.margins: -6
									hoverEnabled: true
									onClicked: win.askCleanFiles()
								}
							}
						}
					Column {
						id: usage

						width: 200
						height: 26
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
					height: parent.height - 26 - 12 - (win.pending ? 44 : 0)
					clip: true

					Treemap {
						anchors.fill: parent
						items: win.children
						selected: win.mapSelection
						onPicked: function (item) { win.toggleMapItem(item); }
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

				Item {
					width: parent.width
					height: win.pending ? 44 : 0
					visible: win.pending !== null

					Rectangle {
						anchors.fill: parent
						color: Config.launcherSearchBox
					}

					Row {
						anchors.left: parent.left
						anchors.leftMargin: 14
						anchors.verticalCenter: parent.verticalCenter
						spacing: 14

						Text {
							anchors.verticalCenter: parent.verticalCenter

							font.family: Config.fontFamily
							font.pixelSize: 12
							color: Config.foreground
							text: win.pending ? ((win.pending.kind === "clean-files" ? "Clean " : "Remove ") + win.pending.label + "  " + win.formatSize(win.pending.size)) : ""
						}

						Text {
							anchors.verticalCenter: parent.verticalCenter

							font.family: Config.fontFamily
							font.pixelSize: 12
							color: confirmMouse.containsMouse ? Config.red : Config.yellow
							text: "Confirm"

							MouseArea {
								id: confirmMouse

								anchors.fill: parent
								hoverEnabled: true
								onClicked: win.confirmPending()
							}
						}

						Text {
							anchors.verticalCenter: parent.verticalCenter

							font.family: Config.fontFamily
							font.pixelSize: 12
							color: cancelMouse.containsMouse ? Config.foreground : Config.dim
							text: "Cancel"

							MouseArea {
								id: cancelMouse

								anchors.fill: parent
								hoverEnabled: true
								onClicked: win.pending = null
							}
						}
					}
				}
			}

			Item {
				anchors.fill: parent
				visible: win.tab === "packages"

				Rectangle {
					anchors.top: parent.top
					anchors.right: parent.right
					anchors.topMargin: 14
					anchors.rightMargin: 22
					width: cleanPackagesLabel.width + 20
					height: 26
					z: 2
					color: cleanPackagesMouse.containsMouse && win.packageSelectionCount > 0 ? Config.launcherHighlight : Config.launcherSearchBox
					opacity: win.packageSelectionCount > 0 ? 1 : 0.5

					Text {
						id: cleanPackagesLabel

						anchors.centerIn: parent

						font.family: Config.fontFamily
						font.pixelSize: 11
						color: Config.foreground
						text: "Clean"
					}

					MouseArea {
						id: cleanPackagesMouse

						anchors.fill: parent
						hoverEnabled: true
						onClicked: if (win.packageSelectionCount > 0) win.askCleanPackages()
					}
				}

				ListView {
					id: packageList

					anchors.fill: parent
					anchors.leftMargin: 22
					anchors.rightMargin: 22
					anchors.topMargin: 50
					anchors.bottomMargin: 22
					clip: true
					model: win.packageRows
					spacing: 1
					cacheBuffer: 500

					delegate: Item {
						id: packageRow

						required property var modelData
						required property int index

						width: packageList.width
						height: 30

						Rectangle {
							anchors.fill: parent
							color: packageHover.containsMouse ? Config.launcherSearchBox : (packageRow.index % 2 === 0 ? Config.surface : Config.launcherSearchBox)
							opacity: packageHover.containsMouse ? 1 : 0.72
						}

						Check {
							anchors.left: parent.left
							anchors.leftMargin: 10
							anchors.verticalCenter: parent.verticalCenter
							checked: win.packageSelection[packageRow.modelData.name] === true
							onToggled: win.togglePackage(packageRow.modelData)
						}

						Text {
							anchors.left: parent.left
							anchors.leftMargin: 38
							anchors.verticalCenter: parent.verticalCenter
							width: Math.max(100, parent.width * 0.38)
							elide: Text.ElideRight

							font.family: Config.fontFamily
							font.pixelSize: 12
							color: Config.foreground
							text: packageRow.modelData.name
						}

						Text {
							anchors.left: parent.left
							anchors.leftMargin: parent.width * 0.40
							anchors.verticalCenter: parent.verticalCenter
							width: parent.width * 0.20
							elide: Text.ElideRight

							font.family: Config.fontFamily
							font.pixelSize: 11
							color: Config.dim
							text: packageRow.modelData.version
						}

						Text {
							anchors.left: parent.left
							anchors.leftMargin: parent.width * 0.61
							anchors.verticalCenter: parent.verticalCenter
							width: parent.width * 0.12
							elide: Text.ElideRight

							font.family: Config.fontFamily
							font.pixelSize: 11
							color: Config.dim
							text: packageRow.modelData.repo + (packageRow.modelData.orphan ? "  orphan" : "")
						}

						Text {
							anchors.right: parent.right
							anchors.rightMargin: 14
							anchors.verticalCenter: parent.verticalCenter
							width: 90
							horizontalAlignment: Text.AlignRight

							font.family: Config.fontFamily
							font.pixelSize: 11
							color: Config.dim
							text: packageRow.modelData.sizeText
						}


						MouseArea {
							id: packageHover

							anchors.fill: parent
							z: -1
							hoverEnabled: true
						}
					}
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

				Rectangle {
					anchors.top: parent.top
					anchors.right: parent.right
					anchors.topMargin: 14
					anchors.rightMargin: 22
					width: cleanCachesLabel.width + 20
					height: 26
					z: 2
					color: cleanCachesMouse.containsMouse && win.cacheSelectionCount > 0 ? Config.launcherHighlight : Config.launcherSearchBox
					opacity: win.cacheSelectionCount > 0 ? 1 : 0.5

					Text {
						id: cleanCachesLabel

						anchors.centerIn: parent

						font.family: Config.fontFamily
						font.pixelSize: 11
						color: Config.foreground
						text: "Clean"
					}

					MouseArea {
						id: cleanCachesMouse

						anchors.fill: parent
						hoverEnabled: true
						onClicked: if (win.cacheSelectionCount > 0) win.askCleanCaches()
					}
				}

				ListView {
					id: cacheList

					anchors.fill: parent
					anchors.leftMargin: 22
					anchors.rightMargin: 22
					anchors.topMargin: 50
					anchors.bottomMargin: 22
					clip: true
					model: win.cacheRows
					spacing: 1
					cacheBuffer: 300

					delegate: Item {
						id: cacheRow

						required property var modelData
						required property int index

						width: cacheList.width
						height: 34

						Rectangle {
							anchors.fill: parent
							color: cacheHover.containsMouse ? Config.launcherSearchBox : (cacheRow.index % 2 === 0 ? Config.surface : Config.launcherSearchBox)
							opacity: cacheHover.containsMouse ? 1 : 0.72
						}

						Check {
							anchors.left: parent.left
							anchors.leftMargin: 10
							anchors.verticalCenter: parent.verticalCenter
							checked: win.cacheSelection[cacheRow.modelData.id] === true
							onToggled: win.toggleCache(cacheRow.modelData)
						}

						Text {
							anchors.left: parent.left
							anchors.leftMargin: 38
							anchors.verticalCenter: parent.verticalCenter
							width: parent.width * 0.24
							elide: Text.ElideRight

							font.family: Config.fontFamily
							font.pixelSize: 12
							color: Config.foreground
							text: cacheRow.modelData.label
						}

						Text {
							anchors.left: parent.left
							anchors.leftMargin: parent.width * 0.28
							anchors.verticalCenter: parent.verticalCenter
							width: parent.width * 0.48
							elide: Text.ElideMiddle

							font.family: Config.fontFamily
							font.pixelSize: 11
							color: Config.dim
							text: cacheRow.modelData.path
						}

						Text {
							anchors.right: parent.right
							anchors.rightMargin: 14
							anchors.verticalCenter: parent.verticalCenter
							width: 90
							horizontalAlignment: Text.AlignRight

							font.family: Config.fontFamily
							font.pixelSize: 11
							color: Config.dim
							text: cacheRow.modelData.sizeText
						}


						MouseArea {
							id: cacheHover

							anchors.fill: parent
							z: -1
							hoverEnabled: true
						}
					}
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

			Item {
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.bottom: parent.bottom
				height: win.pending !== null && win.tab !== "map" ? 44 : 0
				visible: win.pending !== null && win.tab !== "map"

				Rectangle {
					anchors.fill: parent
					color: Config.launcherSearchBox
				}

				Row {
					anchors.left: parent.left
					anchors.leftMargin: 22
					anchors.verticalCenter: parent.verticalCenter
					spacing: 14

					Text {
						anchors.verticalCenter: parent.verticalCenter

						font.family: Config.fontFamily
						font.pixelSize: 12
						color: Config.foreground
						text: win.pending ? ("Clean " + win.pending.label + "  " + win.formatSize(win.pending.size)) : ""
					}

					Text {
						anchors.verticalCenter: parent.verticalCenter

						font.family: Config.fontFamily
						font.pixelSize: 12
						color: confirmMouse2.containsMouse ? Config.red : Config.yellow
						text: "Confirm"

						MouseArea {
							id: confirmMouse2

							anchors.fill: parent
							hoverEnabled: true
							onClicked: win.confirmPending()
						}
					}

					Text {
						anchors.verticalCenter: parent.verticalCenter

						font.family: Config.fontFamily
						font.pixelSize: 12
						color: cancelMouse2.containsMouse ? Config.foreground : Config.dim
						text: "Cancel"

						MouseArea {
							id: cancelMouse2

							anchors.fill: parent
							hoverEnabled: true
							onClicked: win.pending = null
						}
					}
				}
			}
		}
	}
}
