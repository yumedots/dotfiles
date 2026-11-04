//@ pragma Env QML_IMPORT_PATH=/home/gabriel/dotfiles/shell/native/qml
//@ pragma Env QSG_RHI_BACKEND=opengl
//@ pragma AppId com.yudae.vms
import QtQuick
import Quickshell

ShellRoot {
	Loader {
		source: "features/vms/App.qml"
	}
}
