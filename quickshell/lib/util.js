.pragma library

function clamp(value, min, max) {
	return Math.min(Math.max(value, min), max);
}

function snap(value, scale) {
	const unit = scale > 0 ? scale : 1;

	return Math.round(value * unit) / unit;
}

function pick(mono, color, monoColor) {
	return mono ? monoColor : color;
}

function filledCells(pct, cells) {
	return clamp(Math.round((pct / 100) * cells), 0, cells);
}

function scrollIntoView(contentY, height, contentHeight, top, bottom) {
	const max = Math.max(0, contentHeight - height);
	const next = top < contentY ? top : (bottom > contentY + height ? bottom - height : contentY);

	return clamp(next, 0, max);
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
