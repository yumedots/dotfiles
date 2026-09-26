.pragma library

const objectPath = "/org/mpris/MediaPlayer2";
const playerInterface = "org.mpris.MediaPlayer2.Player";
const methods = { playPause: "PlayPause", next: "Next", previous: "Previous" };

function pickPlayer(players) {
	const list = players || [];

	return list.filter(function (player) { return player.isPlaying; })[0] || list[0] || null;
}

function command(players, action) {
	const player = pickPlayer(players);
	const method = methods[action];

	if (!player || !player.dbusName || !method)
		return [];

	return ["busctl", "--user", "call", player.dbusName, objectPath, playerInterface, method];
}
