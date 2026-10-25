pragma Singleton

import QtQuick
import qs

QtObject {
	function clamp(value, min, max) {
		return Math.min(Math.max(value, min), max);
	}

	function roundStep(value, steps) {
		const count = steps > 0 ? steps : 1;

		return Math.round(clamp(value, 0, 1) * count) / count;
	}

	function snap(value, scale) {
		const unit = scale > 0 ? scale : 1;

		return Math.round(value * unit) / unit;
	}

	function pick(mono, color, monoColor) {
		return mono ? monoColor : color;
	}

	function popupSide(alignRight, centered, alwaysCentered, fullscreen) {
		if (alignRight)
			return "right";

		if (!centered)
			return "anchor";

		if (alwaysCentered)
			return "center";

		return fullscreen ? "float" : "anchor";
	}

	function filledCells(pct, cells) {
		return clamp(Math.round((pct / 100) * cells), 0, cells);
	}

	function scrollIntoView(contentY, height, contentHeight, top, bottom) {
		const max = Math.max(0, contentHeight - height);
		const next = top < contentY ? top : (bottom > contentY + height ? bottom - height : contentY);

		return clamp(next, 0, max);
	}

	function pointerMoved(state, at, step = 0) {
		const prev = state;

		if (!prev || prev.seen !== true)
			return { seen: true, x: at.x, y: at.y, engaged: false, moved: false };

		const dx = at.x - prev.x;
		const dy = at.y - prev.y;

		if (dx === 0 && dy === 0)
			return { seen: true, x: prev.x, y: prev.y, engaged: prev.engaged === true, moved: false };

		if (prev.engaged === true || step <= 0 || dx * dx + dy * dy >= step * step)
			return { seen: true, x: at.x, y: at.y, engaged: true, moved: true };

		return { seen: true, x: prev.x, y: prev.y, engaged: false, moved: false };
	}

	function wrap(index, delta, count) {
		if (count <= 0)
			return 0;

		return ((index + delta) % count + count) % count;
	}

	function pageCount(contentWidth, viewWidth, step) {
		if (viewWidth <= 0 || step <= 0 || contentWidth <= viewWidth)
			return 1;

		return Math.ceil((contentWidth - viewWidth) / step) + 1;
	}

	function pageOffset(page, contentWidth, viewWidth, step) {
		const last = Math.max(0, contentWidth - viewWidth);
		const wanted = Math.max(0, Math.floor(page)) * step;

		return clamp(wanted, 0, last);
	}
}
