//@ pragma IconTheme breeze
import QtQuick
import qs
import Quickshell

Root {
	Component.onCompleted: {
		Quickshell.execDetached(["sh", "-c", "pgrep -f '^quickshell -p .*launcherShell\\.qml' >/dev/null || { ulimit -Sn 65536; export MALLOC_ARENA_MAX=2 MALLOC_TRIM_THRESHOLD_=65536 QSG_RENDER_LOOP=basic; setsid quickshell -p \"$HOME/.config/quickshell/launcherShell.qml\" >/dev/null 2>&1 & echo $! > \"$XDG_RUNTIME_DIR/qs-launcher.pid\"; }"])
	}
}
