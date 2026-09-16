.pragma library

const background = "#000000";
const surface = "#101010";
const surfaceAlpha = 1;
const surfaceTranslucent = "#" + ("0" + Math.round(surfaceAlpha * 255).toString(16)).slice(-2) + surface.slice(1);
const foreground = "#ffffff";
const dim = "#3f3f3f";
const red = "#e05252";
const muted = "#5c5c5c";

const workspaceActive = "#ffffff";
const workspaceInactive = "#5c5c5c";

const cpuBase = "#a78bfa";
const cpuIdle = "#2f2f2f";
const memoryBase = "#7bd88f";
const volumeBase = "#ffffff";

const fontFamily = "Hack Nerd Font";
const fontSize = 12;
const valueSample = "0123456789.%G";
const iconSize = 10;
const trayIconSize = 11;
const spacing = 12;
const workspacePadding = 1;
const workspaceSpacing = 6;

const iconCpu = "\uf2db";
const iconMemory = "\uefc5";
const iconBell = "\uf0f3";
const iconDown = "\uf078";
const iconUp = "\uf077";
const iconRight = "\uf054";
const iconVolumeLow = "\uf026";
const iconVolumeMid = "\uf027";
const iconVolumeHigh = "\uf028";

const barCells = 15;
const lineLength = 45;
const barThickness = 1.5;
const barSweepMs = 1400;
const sweepFade = 0.45;
const sweepSteps = 5;

const tooltipOffsetX = 0;
const tooltipOffsetY = -8;
const popupCloseDelay = 60;
const borderFallbackWidth = 1;
const borderFallbackColor = "#ffffff";
const gapsInFallback = 8;
const gapsOutFallback = 15;

const barLayoutFile = "topbarlayout.json";
const clockFormat = "HH:mm";
const dateFormat = "yyyy-MM-dd";

const mixerChannelWidth = 72;
const mixerChannelGap = 6;
const mixerFaderThickness = 4;
const mixerFaderHeight = 64;
const mixerPadding = 12;
const mixerIconSize = 22;
const mixerDeviceIconSize = 26;
const mixerVisibleChannels = 5;
const mixerIdleChannels = 2;
const mixerArrowSize = 14;
const mixerArrowGap = 6;
const mixerRowGap = 10;
const mixerListRowHeight = 20;
const mixerListGap = 8;
const mixerMaxVolume = 1;
const mixerStep = 0.05;
const mixerOnlyPlaying = true;
const mixerPollMs = 1000;
const mixerHoldMs = 2000;
const mixerRecordDotSize = 5;
const iconApp = "\uf001";
const iconOutput = "\u{f0379}";
const iconInput = "\u{f036c}";
const iconPrev = "\u{f0141}";
const iconNext = "\u{f0142}";

const cpuTooltipWidth = 240;
const cpuTooltipPadding = 12;
const cpuBlockGap = 4;
const cpuBlockColumns = 16;
const cpuTopCount = 5;
const memoryTooltipWidth = 240;
const memoryTooltipPadding = 12;
const memoryTopCount = 5;
const memoryCached = "#44774f";
const memoryBuffers = "#25412b";
const memoryFree = "#3f3f3f";
const memorySwap = "#7f8fd8";
const memoryWarn = "#d8b04a";
const memoryDanger = "#e05252";
const memorySeparator = 1;
const memoryWarnAt = 60;
const memoryDangerAt = 85;
const procsGap = 6;
const topProcessTitle = "Top processes";
const psIgnore = ["ps", "ps <defunct>"];
const cpuPollMs = 1000;
const scrollbarWidth = 2;
const procFade = 0.8;
const procFadeOpacity = 0.8;

const procSearchPlaceholder = "Type to search";
const procSearchHint = "f to type";
const procSearchPadding = 4;
const procSearchMinWidth = 140;
const procKillSignal = "-9";
const procNoMatch = "Nothing matches";
const procHintKey = "f";
const procKillKey = "q";

const launcherWidth = 270;
const launcherPadding = 12;
const launcherGap = 8;
const launcherInputHeight = 30;
const launcherRowHeight = 28;
const launcherFontSize = 16;
const launcherIconSize = 20;
const launcherIconSlot = 24;
const launcherTextGap = 10;
const launcherSearchBox = "#1f1f1f";
const launcherHighlight = "#2f2f2f";
const launcherHighlightText = "#ffffff";
const launcherUsageMax = 10;
const launcherTerminalConfig = "~/.config/hypr/programs.lua";
const launcherPrompt = "\uea6d";
const launcherMaxRows = 12;
const launcherMaxResults = 60;
const launcherIgnoreApps = ["avahi-discover", "bssh", "bvnc"];
const launcherFileDepth = 6;
const launcherFileMax = 40;
const launcherFileDebounce = 220;
const launcherFileSkip = [".cache", ".git", "node_modules", ".local", ".cargo", ".rustup", ".npm"];
const launcherMarks = { files: ".", clipboard: "$" };
const launcherIconCommand = "\u{f018c}";
const launcherIconCalc = "\uf00ec";
const launcherIconFiles = "\u{f0967}";
const launcherIconClipboard = "\uf07f";
const launcherIconWindow = "\u{f05b1}";
const launcherIconFile = "\u{f0213}";
const launcherIconPin = "\ueba0";

const launcherCommands = [
	{ name: "Edit shell config", command: "code-insiders ~/.config/quickshell/config.js", keywords: ["quickshell"] },
	{ name: "Edit hyprland config", command: "code-insiders ~/.config/hypr", keywords: ["hypr"] },
	{ name: "Edit launcher shortcuts", command: "code-insiders ~/.config/quickshell/config.js", keywords: ["launcher"] }
];

const launcherActions = [
	{ name: "Suspend", command: "systemctl suspend", glyph: "\u{f04b2}" },
	{ name: "Log out", command: "hyprctl dispatch 'hl.dsp.exit()'", glyph: "\uea6e" },
	{ name: "Reboot", command: "systemctl reboot", glyph: "\u{ead2}" },
	{ name: "Shut down", command: "systemctl poweroff", glyph: "\u{f011}" }
];

const calendarCellWidth = 26;
const calendarCellHeight = 19;
const calendarPadding = 10;
const calendarHeaderHeight = 22;


const notifyBase = foreground;
const notifyWidth = 280;
const notifyPadding = 12;
const notifyPaddingY = 0;
const notifyRowHeight = 38;
const notifyRowPadding = 4;
const notifySlot = 30;
const notifySlotGap = 10;
const notifyBellSize = 28;
const notifyAppFontSize = 11;
const notifyVisibleRows = 5;
const notifyHistory = 50;
const notifyGoneOpacity = 0.55;
const notifyEmpty = "Nothing yet";
const notifySeparator = 1;
const notifySeparatorColor = foreground;
const notifySweepWidth = 30;
const notifyTimeout = 6000;
const notifyDismissKey = "d";
const notifyClearKey = "x";

const dockEnabled = false;
const dockIconSize = 34;
const dockBottomPadding = 12;
const dockTopPadding = dockBottomPadding;
const dockRadius = 18;
const dockSpacing = 18;
const dockSidePadding = dockSpacing;
const dockBottomMargin = 6;
const dockGap = 0;
const dockDotSize = 4;
const dockDotGap = 3;
const dockDotSpacing = 4;
const dockMaxDots = 5;
const dockPlusSize = 9;
const dockSeparatorWidth = 1;
const dockSeparatorHeight = 24;
const dockSeparator = "#3f3f3f";
const dockFallbackIcon = "application-x-executable";
const dockLauncherIcon = "\uf135";
const dockLauncherColor = muted;
const dockLauncherSize = 30;
const dockPinned = ["footclient", "helium", "code-insiders"];
const dockTerminalClasses = ["foot", "footclient"];
