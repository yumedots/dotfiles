.pragma library

const objectPath = "/org/mpris/MediaPlayer2";
const playerInterface = "org.mpris.MediaPlayer2.Player";
const methods = { playPause: "PlayPause", next: "Next", previous: "Previous" };

function hasContent(player) {
	if (!player)
		return false;

	if (player.isPlaying)
		return true;

	return String(player.trackTitle || "") !== "";
}

function pickPlayer(players) {
	const list = players || [];

	return list.filter(function (player) { return player.isPlaying; })[0] || list[0] || null;
}

function timeText(seconds) {
	const total = Math.max(0, Math.floor(Number(seconds) || 0));
	const minutes = Math.floor(total / 60);
	const rest = total % 60;

	if (minutes < 60)
		return minutes + ":" + (rest < 10 ? "0" : "") + rest;

	return Math.floor(minutes / 60) + ":" + (minutes % 60 < 10 ? "0" : "") + (minutes % 60) + ":" + (rest < 10 ? "0" : "") + rest;
}

function clock(player, position) {
	const length = player && player.length > 0 ? player.length : 0;
	const at = length > 0 ? Math.min(Math.max(Number(position) || 0, 0), length) : 0;

	return {
		known: length > 0,
		percent: length > 0 ? 100 * at / length : 0,
		elapsed: timeText(at),
		total: timeText(length)
	};
}

function command(players, action) {
	const player = pickPlayer(players);
	const method = methods[action];

	if (!player || !player.dbusName || !method)
		return [];

	return ["busctl", "--user", "call", player.dbusName, objectPath, playerInterface, method];
}
