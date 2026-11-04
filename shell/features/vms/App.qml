import QtQuick
import Quickshell
import qs.ui
import qs.services
import Yudae.Native

AppWindow {
	appTitle: "Virtual machines"

	VmDisplay {
		anchors.fill: parent
		qmp: (Quickshell.env("YUDAE_VM_ROOT") || "/home/gabriel/dotfiles/vm/runs") + "/" + (Quickshell.env("YUDAE_VM") || "demo") + "/display.qmp"
	}
}
