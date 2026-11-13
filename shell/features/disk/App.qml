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

	function askRemove(row) {
		win.pending = { kind: "uninstall", id: row.name, label: row.name, size: row.size, names: [row.name] };
	}

	function askClean(row) {
		win.pending = { kind: "clean", id: row.id, label: row.label, size: row.size, names: [] };
	}

	function askCleanPackages() {
		Yudae.diskCommand("clean-packages", {}, function (result) {
			if (!result)
				return;

			if (result.ok === true) {
				win.loadPackages();
				return;
			}

			const items = result.items || [];
			const names = [];

			for (let i = 0; i < items.length; i++)
				names.push(items[i].name);

			win.pending = { kind: "clean-packages", id: "", label: names.length + " orphan packages", size: result.space || 0, names: names };
		});
	}

	function confirmPending() {
		if (!win.pending)
			return;

		const action = win.pending;
		win.pending = null;

		if (action.kind === "uninstall" || action.kind === "clean-packages") {
			if (action.kind === "clean-packages") {
				Yudae.diskCommand("clean-packages", { confirm: true }, function () { win.loadPackages(); });
			} else {
				Yudae.diskCommand("uninstall", { names: action.names, confirm: true }, function () {
					win.loadPackages();
				});
			}
			return;
		}

		Yudae.diskCommand("clean", { id: action.id, confirm: true }, function () {
			win.loadCaches();
		});
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
						width: parent.width - parent.spacing - 34 - usage.width
						height: 26
						verticalAlignment: Text.AlignVCenter
						elide: Text.ElideMiddle

						font.family: Config.fontFamily
						font.pixelSize: 12
						color: Config.foreground
						text: win.focus
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
						onPicked: function (item) {
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
							text: win.pending ? ("Remove " + win.pending.label + "  " + win.formatSize(win.pending.size)) : ""
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
					color: cleanPackagesMouse.containsMouse ? Config.launcherHighlight : Config.launcherSearchBox

					Text {
						id: cleanPackagesLabel

						anchors.centerIn: parent

						font.family: Config.fontFamily
						font.pixelSize: 11
						color: Config.foreground
						text: "Clean orphans"
					}

					MouseArea {
						id: cleanPackagesMouse

						anchors.fill: parent
						hoverEnabled: true
						onClicked: win.askCleanPackages()
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

						Text {
							anchors.left: parent.left
							anchors.leftMargin: 10
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
							anchors.rightMargin: 86
							anchors.verticalCenter: parent.verticalCenter
							width: 90
							horizontalAlignment: Text.AlignRight

							font.family: Config.fontFamily
							font.pixelSize: 11
							color: Config.dim
							text: packageRow.modelData.sizeText
						}

						Text {
							anchors.right: parent.right
							anchors.rightMargin: 14
							anchors.verticalCenter: parent.verticalCenter

							font.family: Config.fontFamily
							font.pixelSize: 11
							color: removeMouse.containsMouse ? Config.red : Config.dim
							text: "Remove"

							MouseArea {
								id: removeMouse

								anchors.fill: parent
								anchors.margins: -6
								hoverEnabled: true
								onClicked: win.askRemove(packageRow.modelData)
							}
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

				ListView {
					id: cacheList

					anchors.fill: parent
					anchors.margins: 22
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

						Text {
							anchors.left: parent.left
							anchors.leftMargin: 10
							anchors.verticalCenter: parent.verticalCenter
							width: parent.width * 0.26
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
							anchors.rightMargin: 84
							anchors.verticalCenter: parent.verticalCenter
							width: 90
							horizontalAlignment: Text.AlignRight

							font.family: Config.fontFamily
							font.pixelSize: 11
							color: Config.dim
							text: cacheRow.modelData.sizeText
						}

						Text {
							anchors.right: parent.right
							anchors.rightMargin: 14
							anchors.verticalCenter: parent.verticalCenter

							font.family: Config.fontFamily
							font.pixelSize: 11
							color: cleanMouse.containsMouse ? Config.yellow : Config.dim
							text: "Clean"
							visible: cacheRow.modelData.exists

							MouseArea {
								id: cleanMouse

								anchors.fill: parent
								anchors.margins: -6
								hoverEnabled: true
								onClicked: win.askClean(cacheRow.modelData)
							}
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
						text: win.pending ? (((win.pending.kind === "uninstall" || win.pending.kind === "clean-packages") ? "Remove " : "Clean ") + win.pending.label + "  " + win.formatSize(win.pending.size)) : ""
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
