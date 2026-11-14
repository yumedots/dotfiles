pragma Singleton

import QtQuick

QtObject {
	function clamp(value, min, max) { return Math.min(Math.max(value, min), max); }
}
