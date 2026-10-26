.pragma library

function plainText(html) {
	return String(html || "")
		.replace(/<br\s*\/?>/gi, " ")
		.replace(/<[^>]*>/g, "")
		.replace(/&lt;/g, "<")
		.replace(/&gt;/g, ">")
		.replace(/&quot;/g, "\"")
		.replace(/&#39;/g, "'")
		.replace(/&nbsp;/g, " ")
		.replace(/&amp;/g, "&")
		.replace(/\s+/g, " ")
		.trim();
}

function parseClipboardImage(preview) {
	const match = /^\[\[\s*binary data\s+.*?\b(png|jpe?g|gif|webp|bmp|ico|tiff?)\s+(\d+)\s*x\s*(\d+).*?\]\]$/i.exec(preview || "");

	if (!match)
		return "";

	return match[1].toLowerCase();
}

