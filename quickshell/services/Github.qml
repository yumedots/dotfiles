pragma Singleton

import QtQuick
import Quickshell
import qs

Item {
	id: root

	property string login: ""
	property var days: []
	property int total: 0
	property real fetched: 0
	property bool loading: false
	property string status: ""
	property string dayStamp: root.dayKey(new Date())

	readonly property string dir: Quickshell.shellDir + "/cache/github"
	readonly property string cacheFile: root.dir + "/contrib.json"
	readonly property string suffix: "@users.noreply.github.com"
	readonly property var grid: Contrib.contribGrid(root.days, Config.contribWeeks, root.dayStamp)
	readonly property var today: root.dayOn(new Date())
	readonly property int todayCount: root.today ? root.today.count : 0
	readonly property int todayLevel: root.today ? root.today.level : 0
	readonly property var last: root.days.length > 0 ? root.days[root.days.length - 1] : null

	function dayOn(date) {
		const key = root.dayKey(date);
		return root.days.filter(function (day) {
			return day.date === key;
		})[0] || null;
	}

	function dayKey(date) {
		const pad = function (value) {
			return (value < 10 ? "0" : "") + value;
		};

		return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate());
	}

	function loginFrom(text) {
		const fields = {};

		String(text || "").split("\n").forEach(function (line) {
			const at = line.indexOf("=");

			if (at > 0)
				fields[line.substring(0, at).trim()] = line.substring(at + 1).trim();
		});

		const candidates = [Config.contribUser, root.loginOfEmail(fields.email), root.loginOfRemote(fields.remote), fields.name];

		for (let i = 0; i < candidates.length; i++) {
			if (root.usable(candidates[i]))
				return candidates[i];
		}

		return "";
	}

	function usable(login) {
		return !!login && /^[A-Za-z0-9][A-Za-z0-9-]{0,38}$/.test(login);
	}

	function loginOfEmail(email) {
		const value = String(email || "");

		if (value.indexOf(root.suffix) !== value.length - root.suffix.length)
			return "";

		const head = value.substring(0, value.length - root.suffix.length);
		const plus = head.indexOf("+");

		return plus >= 0 ? head.substring(plus + 1) : head;
	}

	function loginOfRemote(url) {
		const value = String(url || "");
		const at = value.indexOf("github.com");

		if (at < 0)
			return "";

		const rest = value.substring(at + "github.com".length).replace(/^[:/]+/, "");
		const slash = rest.indexOf("/");

		return slash > 0 ? rest.substring(0, slash) : "";
	}

	function adopt(cached) {
		root.login = cached.login || "";
		root.days = cached.days || [];
		root.total = cached.total || 0;
		root.fetched = cached.fetched || 0;
	}

	function save() {
		cache.save({
			fetched: root.fetched,
			login: root.login,
			total: root.total,
			days: root.days
		});
	}

	function refresh(force) {
		if (root.loading)
			return;

		root.loading = true;
		cache.read(force);
	}

	Component.onCompleted: root.refresh(false)

	Timer {
		interval: 60000
		running: true
		repeat: true

		onTriggered: root.dayStamp = root.dayKey(new Date())
	}

	CachedFile {
		id: cache

		path: root.cacheFile
		maxAge: Config.contribCacheMs

		onLoaded: function (data, stale) {
			root.adopt(data);

			if (!stale && root.days.length > 0) {
				root.loading = false;
				root.status = "";
				return;
			}

			identity.running = true;
		}
	}

	Request {
		id: identity

		command: ["sh", "-c", "printf 'email=%s\\n' \"$(git config --get user.email)\"; printf 'name=%s\\n' \"$(git config --global user.name)\"; printf 'remote=%s\\n' \"$(git -C \"$HOME/.config\" remote get-url origin 2>/dev/null)\""]

		onDone: function (text) {
			const login = root.loginFrom(text);

			if (login === "") {
				root.loading = false;
				root.status = "no GitHub user";
				return;
			}

			root.login = login;
			fetch.running = true;
		}
	}

	Request {
		id: fetch

		command: Shell.curl("https://github.com/users/" + root.login + "/contributions", 20)

		onDone: function (text) {
			const parsed = Contrib.parseContributions(text);

			root.loading = false;

			if (parsed.days.length === 0) {
				root.status = root.days.length > 0 ? "" : "no response";
				return;
			}

			root.days = parsed.days;
			root.total = parsed.total;
			root.fetched = Date.now();
			root.status = "";
			root.save();
		}
	}
}
