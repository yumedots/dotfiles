.pragma library

function rateText(bytesPerSecond) {
	const value = Math.max(0, Number(bytesPerSecond) || 0);

	if (value >= 1024 * 1024)
		return (value / 1024 / 1024).toFixed(1) + " MB/s";

	if (value >= 1024)
		return (value / 1024).toFixed(0) + " KB/s";

	return Math.round(value) + " B/s";
}

function brailleMasks(values, peak, cells, dir) {
	const cols = cells * 2;
	const top = peak > 0 ? peak : 1;
	const quiet = 16 * 1024;
	const count = values.length;
	const masks = [];

	let i = count - cols;

	for (let c = 0; c < cells; c++) {
		let mask = 0;

		for (let k = 0; k < 2; k++) {
			const sample = i >= 0 && i < count ? values[i] : 0;

			i++;
			const value = Math.max(0, Number(sample) || 0);
			const lit = value < quiet ? 0 : Math.min(4, Math.floor(value / top * 4 + 0.5));

			if (lit > 0) {
				const dots = (1 << lit) - 1;
				mask |= dir === "up" ? dots << (k * 4) : dots << (4 - lit) << (k * 4);
			}
		}

		masks.push(mask);
	}

	return masks;
}

function signalBars(pct) {
	const value = Math.max(0, Math.min(100, Number(pct) || 0));

	if (value > 80)
		return 4;

	if (value > 55)
		return 3;

	if (value > 30)
		return 2;

	return value > 5 ? 1 : 0;
}

function megaBits(bytesPerSecond) {
	return Math.max(0, Number(bytesPerSecond) || 0) * 8 / 1000000;
}

function speedText(bytesPerSecond) {
	return megaBits(bytesPerSecond).toFixed(0);
}

function speedCeiling(bytesPerSecond) {
	const ladder = [5, 10, 25, 50, 100, 250, 500, 1000];
	const mbps = megaBits(bytesPerSecond) * 1.5;

	for (let i = 0; i < ladder.length; i++)
		if (mbps < ladder[i])
			return ladder[i] * 125000;

	return ladder[ladder.length - 1] * 125000;
}
