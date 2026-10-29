pragma Singleton

import QtQuick
import qs.services

QtObject {
	id: root

	readonly property var settings: Yudae.settings || ({})

	// base surface, ink and the mono ink that replaces the hue when mono is on
	readonly property var surface: settings.surface !== undefined ? settings.surface : "#101010"
	readonly property var surfaceAlpha: settings.surfaceAlpha !== undefined ? settings.surfaceAlpha : 1
	readonly property var surfaceTranslucent: settings.surfaceTranslucent !== undefined ? settings.surfaceTranslucent : "#ff101010"
	readonly property var foreground: settings.foreground !== undefined ? settings.foreground : "#ffffff"
	readonly property var dim: settings.dim !== undefined ? settings.dim : "#3f3f3f"
	readonly property var red: settings.red !== undefined ? settings.red : "#e05252"
	readonly property var muted: settings.muted !== undefined ? settings.muted : "#5c5c5c"
	readonly property var mono: settings.mono !== undefined ? settings.mono : true
	readonly property var monoLight: settings.monoLight !== undefined ? settings.monoLight : "#cfcfcf"
	readonly property var monoMid: settings.monoMid !== undefined ? settings.monoMid : "#9a9a9a"
	readonly property var monoSoft: settings.monoSoft !== undefined ? settings.monoSoft : "#6f6f6f"

	// things that are not a widget: font, spacing, workspace morph
	readonly property var workspaceSpacing: settings.workspaceSpacing !== undefined ? settings.workspaceSpacing : 6
	readonly property var workspaceMorphMs: settings.workspaceMorphMs !== undefined ? settings.workspaceMorphMs : 320
	readonly property var figureLobes: settings.figureLobes !== undefined ? settings.figureLobes : 9
	readonly property var figureScallop: settings.figureScallop !== undefined ? settings.figureScallop : 0.16
	readonly property var fontFamily: settings.fontFamily !== undefined ? settings.fontFamily : "GoogleSansCode Nerd Font"
	readonly property var fontSize: settings.fontSize !== undefined ? settings.fontSize : 12
	readonly property var valueSample: settings.valueSample !== undefined ? settings.valueSample : "0123456789.%G"
	readonly property var iconSize: settings.iconSize !== undefined ? settings.iconSize : 10
	readonly property var spacing: settings.spacing !== undefined ? settings.spacing : 12
	readonly property var lineLength: settings.lineLength !== undefined ? settings.lineLength : 45
	readonly property var scrollbarWidth: settings.scrollbarWidth !== undefined ? settings.scrollbarWidth : 2
	readonly property var gapsIn: settings.gapsIn !== undefined ? settings.gapsIn : 4
	readonly property var gapsOut: settings.gapsOut !== undefined ? settings.gapsOut : 8

	// tray icons and their menu
	readonly property var trayIconSize: settings.trayIconSize !== undefined ? settings.trayIconSize : 15
	readonly property var trayIconGap: settings.trayIconGap !== undefined ? settings.trayIconGap : 10
	readonly property var trayGroupSize: settings.trayGroupSize !== undefined ? settings.trayGroupSize : 15
	readonly property var trayChevronBoost: settings.trayChevronBoost !== undefined ? settings.trayChevronBoost : 1
	readonly property var trayMenuWidth: settings.trayMenuWidth !== undefined ? settings.trayMenuWidth : 120
	readonly property var trayMenuPadding: settings.trayMenuPadding !== undefined ? settings.trayMenuPadding : 6
	readonly property var trayMenuRowHeight: settings.trayMenuRowHeight !== undefined ? settings.trayMenuRowHeight : 18
	readonly property var trayMenuSeparator: settings.trayMenuSeparator !== undefined ? settings.trayMenuSeparator : 1

	// the bar itself, its cells and the sweep that runs through them
	readonly property var barHitPadding: settings.barHitPadding !== undefined ? settings.barHitPadding : 4
	readonly property var barStatSpacing: settings.barStatSpacing !== undefined ? settings.barStatSpacing : 16
	readonly property var barCells: settings.barCells !== undefined ? settings.barCells : 15
	readonly property var barInset: settings.barInset !== undefined ? settings.barInset : 8
	readonly property var barPadding: settings.barPadding !== undefined ? settings.barPadding : 8
	readonly property var barFloating: settings.barFloating !== undefined ? settings.barFloating : false
	readonly property var barBorderWidth: settings.barBorderWidth !== undefined ? settings.barBorderWidth : 0
	readonly property var barStatMode: settings.barStatMode !== undefined ? settings.barStatMode : "icon"
	readonly property var barStatMono: settings.barStatMono !== undefined ? settings.barStatMono : true
	readonly property var barThickness: settings.barThickness !== undefined ? settings.barThickness : 1.5
	readonly property var barSweepMs: settings.barSweepMs !== undefined ? settings.barSweepMs : 1400
	readonly property var sweepFade: settings.sweepFade !== undefined ? settings.sweepFade : 0.45
	readonly property var sweepSteps: settings.sweepSteps !== undefined ? settings.sweepSteps : 5
	readonly property var clockFormat: settings.clockFormat !== undefined ? settings.clockFormat : "ddd MMM d h:mm AP"
	readonly property var borderFallbackWidth: settings.borderFallbackWidth !== undefined ? settings.borderFallbackWidth : 1
	readonly property var borderFallbackColor: settings.borderFallbackColor !== undefined ? settings.borderFallbackColor : "#ffffff"

	// every panel's fade, slide and position
	readonly property var popupCloseDelay: settings.popupCloseDelay !== undefined ? settings.popupCloseDelay : 60
	readonly property var popupFadeMs: settings.popupFadeMs !== undefined ? settings.popupFadeMs : 140
	readonly property var popupSlideMs: settings.popupSlideMs !== undefined ? settings.popupSlideMs : 400
	readonly property var barFadeMs: settings.barFadeMs !== undefined ? settings.barFadeMs : 300
	readonly property var popupPos: settings.popupPos !== undefined ? settings.popupPos : "top-center"
	readonly property var popupX: settings.popupX !== undefined ? settings.popupX : -1
	readonly property var popupY: settings.popupY !== undefined ? settings.popupY : -1
	readonly property var popupBorderWidth: settings.popupBorderWidth !== undefined ? settings.popupBorderWidth : 1
	readonly property var volumeOsdMs: settings.volumeOsdMs !== undefined ? settings.volumeOsdMs : 1500

	// the tooltip body and its close button
	readonly property var tooltipCloseSize: settings.tooltipCloseSize !== undefined ? settings.tooltipCloseSize : 14
	readonly property var tooltipCloseInset: settings.tooltipCloseInset !== undefined ? settings.tooltipCloseInset : 6
	readonly property var tooltipOffsetX: settings.tooltipOffsetX !== undefined ? settings.tooltipOffsetX : 0
	readonly property var tooltipGap: settings.tooltipGap !== undefined ? settings.tooltipGap : 7
	readonly property var tooltipGapRight: settings.tooltipGapRight !== undefined ? settings.tooltipGapRight : 3
	readonly property var tooltipHang: settings.tooltipHang !== undefined ? settings.tooltipHang : 3

	// nerd font glyphs
	readonly property var iconClose: settings.iconClose !== undefined ? settings.iconClose : "\uf00d"
	readonly property var iconCpu: settings.iconCpu !== undefined ? settings.iconCpu : "\uf2db"
	readonly property var iconChevron: settings.iconChevron !== undefined ? settings.iconChevron : "\uf053"
	readonly property var iconMemory: settings.iconMemory !== undefined ? settings.iconMemory : "\uefc5"
	readonly property var iconBell: settings.iconBell !== undefined ? settings.iconBell : "\uf0f3"
	readonly property var iconDown: settings.iconDown !== undefined ? settings.iconDown : "\uf078"
	readonly property var iconUp: settings.iconUp !== undefined ? settings.iconUp : "\uf077"
	readonly property var iconRight: settings.iconRight !== undefined ? settings.iconRight : "\uf054"
	readonly property var iconGithub: settings.iconGithub !== undefined ? settings.iconGithub : "\uf09b"
	readonly property var iconVolumeLow: settings.iconVolumeLow !== undefined ? settings.iconVolumeLow : "\uf026"
	readonly property var iconVolumeMid: settings.iconVolumeMid !== undefined ? settings.iconVolumeMid : "\uf027"
	readonly property var iconVolumeHigh: settings.iconVolumeHigh !== undefined ? settings.iconVolumeHigh : "\uf028"
	readonly property var iconPlay: settings.iconPlay !== undefined ? settings.iconPlay : "\uf04b"
	readonly property var iconPause: settings.iconPause !== undefined ? settings.iconPause : "\uf04c"
	readonly property var iconApp: settings.iconApp !== undefined ? settings.iconApp : "\uf001"
	readonly property var iconOutput: settings.iconOutput !== undefined ? settings.iconOutput : "\udb80\udf79"
	readonly property var iconInput: settings.iconInput !== undefined ? settings.iconInput : "\udb80\udf6c"
	readonly property var iconPrev: settings.iconPrev !== undefined ? settings.iconPrev : "\udb80\udd41"
	readonly property var iconNext: settings.iconNext !== undefined ? settings.iconNext : "\udb80\udd42"
	readonly property var iconDisplay: settings.iconDisplay !== undefined ? settings.iconDisplay : "\udb80\udf79"
	readonly property var iconPowerPlug: settings.iconPowerPlug !== undefined ? settings.iconPowerPlug : "\udb81\udea5"
	readonly property var iconBatteryFull: settings.iconBatteryFull !== undefined ? settings.iconBatteryFull : "\udb80\udc82"
	readonly property var iconBatteryHigh: settings.iconBatteryHigh !== undefined ? settings.iconBatteryHigh : "\udb80\udc81"
	readonly property var iconBatteryMid: settings.iconBatteryMid !== undefined ? settings.iconBatteryMid : "\udb80\udc7f"
	readonly property var iconBatteryLow: settings.iconBatteryLow !== undefined ? settings.iconBatteryLow : "\udb80\udc7c"
	readonly property var iconBatteryAlert: settings.iconBatteryAlert !== undefined ? settings.iconBatteryAlert : "\udb80\udc83"
	readonly property var iconBatteryCharge: settings.iconBatteryCharge !== undefined ? settings.iconBatteryCharge : "\udb80\udc84"

	// cpu and process list
	readonly property var cpuBase: settings.cpuBase !== undefined ? settings.cpuBase : "#a78bfa"
	readonly property var cpuBaseMono: settings.cpuBaseMono !== undefined ? settings.cpuBaseMono : "#ffffff"
	readonly property var cpuPeak: settings.cpuPeak !== undefined ? settings.cpuPeak : "#e05252"
	readonly property var cpuPeakMono: settings.cpuPeakMono !== undefined ? settings.cpuPeakMono : "#9a9a9a"
	readonly property var cpuIdle: settings.cpuIdle !== undefined ? settings.cpuIdle : "#2f2f2f"
	readonly property var cpuPollMs: settings.cpuPollMs !== undefined ? settings.cpuPollMs : 1000
	readonly property var cpuTopCount: settings.cpuTopCount !== undefined ? settings.cpuTopCount : 5
	readonly property var cpuTooltipWidth: settings.cpuTooltipWidth !== undefined ? settings.cpuTooltipWidth : 240
	readonly property var cpuTooltipPadding: settings.cpuTooltipPadding !== undefined ? settings.cpuTooltipPadding : 12
	readonly property var cpuBlockGap: settings.cpuBlockGap !== undefined ? settings.cpuBlockGap : 4
	readonly property var cpuBlockColumns: settings.cpuBlockColumns !== undefined ? settings.cpuBlockColumns : 16
	readonly property var topProcessTitle: settings.topProcessTitle !== undefined ? settings.topProcessTitle : "Top processes"
	readonly property var procsGap: settings.procsGap !== undefined ? settings.procsGap : 6
	readonly property var psIgnore: settings.psIgnore !== undefined ? settings.psIgnore : ["ps", "ps <defunct>"]
	readonly property var procSearchHint: settings.procSearchHint !== undefined ? settings.procSearchHint : "f to type"
	readonly property var procSearchPadding: settings.procSearchPadding !== undefined ? settings.procSearchPadding : 4
	readonly property var procSearchMinWidth: settings.procSearchMinWidth !== undefined ? settings.procSearchMinWidth : 140
	readonly property var procKillSignal: settings.procKillSignal !== undefined ? settings.procKillSignal : "-9"
	readonly property var procNoMatch: settings.procNoMatch !== undefined ? settings.procNoMatch : "Nothing matches"
	readonly property var procHintKey: settings.procHintKey !== undefined ? settings.procHintKey : "f"
	readonly property var procKillKey: settings.procKillKey !== undefined ? settings.procKillKey : "q"
	readonly property var terminalClasses: settings.terminalClasses !== undefined ? settings.terminalClasses : ["foot", "footclient"]

	// memory bars and tooltip
	readonly property var memoryBase: settings.memoryBase !== undefined ? settings.memoryBase : "#7bd88f"
	readonly property var memoryBaseMono: settings.memoryBaseMono !== undefined ? settings.memoryBaseMono : "#ffffff"
	readonly property var memoryCached: settings.memoryCached !== undefined ? settings.memoryCached : "#44774f"
	readonly property var memoryCachedMono: settings.memoryCachedMono !== undefined ? settings.memoryCachedMono : "#cfcfcf"
	readonly property var memoryBuffers: settings.memoryBuffers !== undefined ? settings.memoryBuffers : "#2f5136"
	readonly property var memoryBuffersMono: settings.memoryBuffersMono !== undefined ? settings.memoryBuffersMono : "#9a9a9a"
	readonly property var memoryFree: settings.memoryFree !== undefined ? settings.memoryFree : "#3f3f3f"
	readonly property var memorySwap: settings.memorySwap !== undefined ? settings.memorySwap : "#ffffff"
	readonly property var memoryWarn: settings.memoryWarn !== undefined ? settings.memoryWarn : "#d8b04a"
	readonly property var memoryWarnMono: settings.memoryWarnMono !== undefined ? settings.memoryWarnMono : "#cfcfcf"
	readonly property var memoryDanger: settings.memoryDanger !== undefined ? settings.memoryDanger : "#e05252"
	readonly property var memoryDangerMono: settings.memoryDangerMono !== undefined ? settings.memoryDangerMono : "#6f6f6f"
	readonly property var memorySeparator: settings.memorySeparator !== undefined ? settings.memorySeparator : 3
	readonly property var memorySeparatorColor: settings.memorySeparatorColor !== undefined ? settings.memorySeparatorColor : "#101010"
	readonly property var memoryVizHeight: settings.memoryVizHeight !== undefined ? settings.memoryVizHeight : 12
	readonly property var memoryWarnAt: settings.memoryWarnAt !== undefined ? settings.memoryWarnAt : 60
	readonly property var memoryDangerAt: settings.memoryDangerAt !== undefined ? settings.memoryDangerAt : 85
	readonly property var memoryTooltipWidth: settings.memoryTooltipWidth !== undefined ? settings.memoryTooltipWidth : 240
	readonly property var memoryTooltipPadding: settings.memoryTooltipPadding !== undefined ? settings.memoryTooltipPadding : 12
	readonly property var memoryTopCount: settings.memoryTopCount !== undefined ? settings.memoryTopCount : 5

	// volume mixer
	readonly property var mixerWidth: settings.mixerWidth !== undefined ? settings.mixerWidth : 246
	readonly property var mixerChannelGap: settings.mixerChannelGap !== undefined ? settings.mixerChannelGap : 6
	readonly property var mixerFaderThickness: settings.mixerFaderThickness !== undefined ? settings.mixerFaderThickness : 4
	readonly property var mixerPadding: settings.mixerPadding !== undefined ? settings.mixerPadding : 12
	readonly property var mixerIconSize: settings.mixerIconSize !== undefined ? settings.mixerIconSize : 22
	readonly property var mixerDeviceIconSize: settings.mixerDeviceIconSize !== undefined ? settings.mixerDeviceIconSize : 26
	readonly property var mixerListRowHeight: settings.mixerListRowHeight !== undefined ? settings.mixerListRowHeight : 20
	readonly property var mixerListGap: settings.mixerListGap !== undefined ? settings.mixerListGap : 8
	readonly property var mixerMaxVolume: settings.mixerMaxVolume !== undefined ? settings.mixerMaxVolume : 1
	readonly property var mixerStepCount: settings.mixerStepCount !== undefined ? settings.mixerStepCount : 10
	readonly property var mixerStep: settings.mixerStep !== undefined ? settings.mixerStep : 0.1
	readonly property var mixerShiftStep: settings.mixerShiftStep !== undefined ? settings.mixerShiftStep : 0.05
	readonly property var mixerOnlyPlaying: settings.mixerOnlyPlaying !== undefined ? settings.mixerOnlyPlaying : true
	readonly property var mixerPollMs: settings.mixerPollMs !== undefined ? settings.mixerPollMs : 1000
	readonly property var mixerHoldMs: settings.mixerHoldMs !== undefined ? settings.mixerHoldMs : 2000
	readonly property var mixerRecordDotSize: settings.mixerRecordDotSize !== undefined ? settings.mixerRecordDotSize : 5
	readonly property var mixerHitPad: settings.mixerHitPad !== undefined ? settings.mixerHitPad : 6

	// now playing
	readonly property var mediaTooltipWidth: settings.mediaTooltipWidth !== undefined ? settings.mediaTooltipWidth : 228
	readonly property var mediaTooltipPadding: settings.mediaTooltipPadding !== undefined ? settings.mediaTooltipPadding : 12
	readonly property var mediaArtHeight: settings.mediaArtHeight !== undefined ? settings.mediaArtHeight : 228
	readonly property var mediaTitleSize: settings.mediaTitleSize !== undefined ? settings.mediaTitleSize : 16
	readonly property var mediaRowGap: settings.mediaRowGap !== undefined ? settings.mediaRowGap : 6
	readonly property var mediaButtonGlyphSize: settings.mediaButtonGlyphSize !== undefined ? settings.mediaButtonGlyphSize : 16
	readonly property var mediaButtonGap: settings.mediaButtonGap !== undefined ? settings.mediaButtonGap : 18
	readonly property var mediaTextGap: settings.mediaTextGap !== undefined ? settings.mediaTextGap : 8
	readonly property var mediaLineGap: settings.mediaLineGap !== undefined ? settings.mediaLineGap : 2
	readonly property var mediaTickMs: settings.mediaTickMs !== undefined ? settings.mediaTickMs : 1000
	readonly property var mediaEmpty: settings.mediaEmpty !== undefined ? settings.mediaEmpty : "Nothing playing"
	readonly property var volumeBase: settings.volumeBase !== undefined ? settings.volumeBase : "#ffffff"

	// launcher box
	readonly property var launcherWidth: settings.launcherWidth !== undefined ? settings.launcherWidth : 270
	readonly property var launcherPadding: settings.launcherPadding !== undefined ? settings.launcherPadding : 12
	readonly property var launcherGap: settings.launcherGap !== undefined ? settings.launcherGap : 8
	readonly property var launcherInputHeight: settings.launcherInputHeight !== undefined ? settings.launcherInputHeight : 30
	readonly property var launcherRowHeight: settings.launcherRowHeight !== undefined ? settings.launcherRowHeight : 28
	readonly property var launcherFontSize: settings.launcherFontSize !== undefined ? settings.launcherFontSize : 16
	readonly property var launcherIconSize: settings.launcherIconSize !== undefined ? settings.launcherIconSize : 20
	readonly property var launcherIconSlot: settings.launcherIconSlot !== undefined ? settings.launcherIconSlot : 24
	readonly property var launcherTextGap: settings.launcherTextGap !== undefined ? settings.launcherTextGap : 10
	readonly property var launcherSearchBox: settings.launcherSearchBox !== undefined ? settings.launcherSearchBox : "#1f1f1f"
	readonly property var launcherHighlight: settings.launcherHighlight !== undefined ? settings.launcherHighlight : "#2f2f2f"
	readonly property var launcherHighlightText: settings.launcherHighlightText !== undefined ? settings.launcherHighlightText : "#ffffff"
	readonly property var launcherPrompt: settings.launcherPrompt !== undefined ? settings.launcherPrompt : "\uea6d"
	readonly property var launcherMaxRows: settings.launcherMaxRows !== undefined ? settings.launcherMaxRows : 12
	readonly property var launcherIconPin: settings.launcherIconPin !== undefined ? settings.launcherIconPin : "\ueba0"
	readonly property var launcherIconActive: settings.launcherIconActive !== undefined ? settings.launcherIconActive : "\uf00c"

	// wallpaper picker
	readonly property var wallpaperTransitionMs: settings.wallpaperTransitionMs !== undefined ? settings.wallpaperTransitionMs : 400
	readonly property var wallpaperEmpty: settings.wallpaperEmpty !== undefined ? settings.wallpaperEmpty : "No wallpapers found"
	readonly property var wallpaperPickerWidth: settings.wallpaperPickerWidth !== undefined ? settings.wallpaperPickerWidth : 1100
	readonly property var wallpaperStageWidth: settings.wallpaperStageWidth !== undefined ? settings.wallpaperStageWidth : 680
	readonly property var wallpaperPreviewRatio: settings.wallpaperPreviewRatio !== undefined ? settings.wallpaperPreviewRatio : 1.78
	readonly property var wallpaperPickerPadding: settings.wallpaperPickerPadding !== undefined ? settings.wallpaperPickerPadding : 16
	readonly property var wallpaperSectionGap: settings.wallpaperSectionGap !== undefined ? settings.wallpaperSectionGap : 16
	readonly property var wallpaperColumns: settings.wallpaperColumns !== undefined ? settings.wallpaperColumns : 3
	readonly property var wallpaperTileGap: settings.wallpaperTileGap !== undefined ? settings.wallpaperTileGap : 8
	readonly property var wallpaperNameSize: settings.wallpaperNameSize !== undefined ? settings.wallpaperNameSize : 13
	readonly property var wallpaperHoverScale: settings.wallpaperHoverScale !== undefined ? settings.wallpaperHoverScale : 1.04
	readonly property var wallpaperTileDim: settings.wallpaperTileDim !== undefined ? settings.wallpaperTileDim : 0.6
	readonly property var wallpaperThumbJobs: settings.wallpaperThumbJobs !== undefined ? settings.wallpaperThumbJobs : 4
	readonly property var wallpaperThumbQuality: settings.wallpaperThumbQuality !== undefined ? settings.wallpaperThumbQuality : 82
	readonly property var wallpaperRingWidth: settings.wallpaperRingWidth !== undefined ? settings.wallpaperRingWidth : 2
	readonly property var wallpaperMarkSize: settings.wallpaperMarkSize !== undefined ? settings.wallpaperMarkSize : 11
	readonly property var wallpaperFadeMs: settings.wallpaperFadeMs !== undefined ? settings.wallpaperFadeMs : 160
	readonly property var wallpaperScrim: settings.wallpaperScrim !== undefined ? settings.wallpaperScrim : 0.45
	readonly property var wallpaperScrimMs: settings.wallpaperScrimMs !== undefined ? settings.wallpaperScrimMs : 180

	// window switcher
	readonly property var windowsGridCell: settings.windowsGridCell !== undefined ? settings.windowsGridCell : 92
	readonly property var windowsRowMargin: settings.windowsRowMargin !== undefined ? settings.windowsRowMargin : 60
	readonly property var windowsHighlightSize: settings.windowsHighlightSize !== undefined ? settings.windowsHighlightSize : 84
	readonly property var windowsLabelGap: settings.windowsLabelGap !== undefined ? settings.windowsLabelGap : 2
	readonly property var windowStepMs: settings.windowStepMs !== undefined ? settings.windowStepMs : 80
	readonly property var windowsIconSize: settings.windowsIconSize !== undefined ? settings.windowsIconSize : 76
	readonly property var windowsTitleSize: settings.windowsTitleSize !== undefined ? settings.windowsTitleSize : 11

	// power menu and battery
	readonly property var powerActions: settings.powerActions !== undefined ? settings.powerActions : [
		{ name: "Suspend", command: "systemctl suspend", glyph: "\udb81\udcb2" },
		{ name: "Log out", command: "hyprctl dispatch 'hl.dsp.exit()'", glyph: "\uea6e" },
		{ name: "Reboot", command: "systemctl reboot", glyph: "\uead2" },
		{ name: "Shut down", command: "systemctl poweroff", glyph: "\uf011" }
	]
	readonly property var powerCellSize: settings.powerCellSize !== undefined ? settings.powerCellSize : 96
	readonly property var powerIconSize: settings.powerIconSize !== undefined ? settings.powerIconSize : 48
	readonly property var powerHighlightSize: settings.powerHighlightSize !== undefined ? settings.powerHighlightSize : 80
	readonly property var powerLabelSize: settings.powerLabelSize !== undefined ? settings.powerLabelSize : 12
	readonly property var powerBase: settings.powerBase !== undefined ? settings.powerBase : "#7bd88f"
	readonly property var powerBaseMono: settings.powerBaseMono !== undefined ? settings.powerBaseMono : "#ffffff"
	readonly property var powerWarn: settings.powerWarn !== undefined ? settings.powerWarn : "#d8b04a"
	readonly property var powerWarnMono: settings.powerWarnMono !== undefined ? settings.powerWarnMono : "#cfcfcf"
	readonly property var powerDanger: settings.powerDanger !== undefined ? settings.powerDanger : "#e05252"
	readonly property var powerDangerMono: settings.powerDangerMono !== undefined ? settings.powerDangerMono : "#6f6f6f"
	readonly property var powerWarnAt: settings.powerWarnAt !== undefined ? settings.powerWarnAt : 30
	readonly property var powerDangerAt: settings.powerDangerAt !== undefined ? settings.powerDangerAt : 15
	readonly property var powerTooltipWidth: settings.powerTooltipWidth !== undefined ? settings.powerTooltipWidth : 240
	readonly property var powerTooltipPadding: settings.powerTooltipPadding !== undefined ? settings.powerTooltipPadding : 12
	readonly property var powerTopCount: settings.powerTopCount !== undefined ? settings.powerTopCount : 5
	readonly property var powerTitle: settings.powerTitle !== undefined ? settings.powerTitle : "Power"
	readonly property var powerGovernorTitle: settings.powerGovernorTitle !== undefined ? settings.powerGovernorTitle : "Governor"
	readonly property var powerWarnText: settings.powerWarnText !== undefined ? settings.powerWarnText : "low battery"
	readonly property var powerNoBattery: settings.powerNoBattery !== undefined ? settings.powerNoBattery : "No battery"
	readonly property var powerDrainTitle: settings.powerDrainTitle !== undefined ? settings.powerDrainTitle : "Top consumers"

	// calendar, meters and the life dial
	readonly property var calendarCellWidth: settings.calendarCellWidth !== undefined ? settings.calendarCellWidth : 60
	readonly property var calendarCellHeight: settings.calendarCellHeight !== undefined ? settings.calendarCellHeight : 34
	readonly property var calendarRows: settings.calendarRows !== undefined ? settings.calendarRows : 6
	readonly property var calendarWeekStart: settings.calendarWeekStart !== undefined ? settings.calendarWeekStart : 1
	readonly property var calendarCursor: settings.calendarCursor !== undefined ? settings.calendarCursor : "#ffffff"
	readonly property var calendarCursorBorder: settings.calendarCursorBorder !== undefined ? settings.calendarCursorBorder : 1
	readonly property var calendarPadding: settings.calendarPadding !== undefined ? settings.calendarPadding : 16
	readonly property var calendarBase: settings.calendarBase !== undefined ? settings.calendarBase : "#ffffff"
	readonly property var calendarIconDay: settings.calendarIconDay !== undefined ? settings.calendarIconDay : "\uf017"
	readonly property var calendarIconMonth: settings.calendarIconMonth !== undefined ? settings.calendarIconMonth : "\uf133"
	readonly property var calendarIconYear: settings.calendarIconYear !== undefined ? settings.calendarIconYear : "\uf254"
	readonly property var calendarIconLife: settings.calendarIconLife !== undefined ? settings.calendarIconLife : "\uf004"
	readonly property var calendarMonthSize: settings.calendarMonthSize !== undefined ? settings.calendarMonthSize : 30
	readonly property var calendarTitleGap: settings.calendarTitleGap !== undefined ? settings.calendarTitleGap : 12
	readonly property var calendarWeekdaySize: settings.calendarWeekdaySize !== undefined ? settings.calendarWeekdaySize : 14
	readonly property var calendarDaySize: settings.calendarDaySize !== undefined ? settings.calendarDaySize : 20
	readonly property var calendarArrowSize: settings.calendarArrowSize !== undefined ? settings.calendarArrowSize : 18
	readonly property var calendarArrowGap: settings.calendarArrowGap !== undefined ? settings.calendarArrowGap : 12
	readonly property var calendarTodayBox: settings.calendarTodayBox !== undefined ? settings.calendarTodayBox : "#1f1f1f"
	readonly property var calendarTrack: settings.calendarTrack !== undefined ? settings.calendarTrack : "#1f1f1f"
	readonly property var calendarGap: settings.calendarGap !== undefined ? settings.calendarGap : 16
	readonly property var calendarMeterHeight: settings.calendarMeterHeight !== undefined ? settings.calendarMeterHeight : 8
	readonly property var calendarMeterRow: settings.calendarMeterRow !== undefined ? settings.calendarMeterRow : 26
	readonly property var calendarMeterGap: settings.calendarMeterGap !== undefined ? settings.calendarMeterGap : 8
	readonly property var calendarMeterLabelSize: settings.calendarMeterLabelSize !== undefined ? settings.calendarMeterLabelSize : 15
	readonly property var calendarMeterValueSize: settings.calendarMeterValueSize !== undefined ? settings.calendarMeterValueSize : 18
	readonly property var calendarMeterLabelWidth: settings.calendarMeterLabelWidth !== undefined ? settings.calendarMeterLabelWidth : 96
	readonly property var calendarMeterValueWidth: settings.calendarMeterValueWidth !== undefined ? settings.calendarMeterValueWidth : 64
	readonly property var calendarDialSize: settings.calendarDialSize !== undefined ? settings.calendarDialSize : 116
	readonly property var calendarDialRingWidth: settings.calendarDialRingWidth !== undefined ? settings.calendarDialRingWidth : 6
	readonly property var calendarDialGlyphSize: settings.calendarDialGlyphSize !== undefined ? settings.calendarDialGlyphSize : 23
	readonly property var calendarDialMoonLift: settings.calendarDialMoonLift !== undefined ? settings.calendarDialMoonLift : 5
	readonly property var calendarDialDayStart: settings.calendarDialDayStart !== undefined ? settings.calendarDialDayStart : 6
	readonly property var calendarDialDayEnd: settings.calendarDialDayEnd !== undefined ? settings.calendarDialDayEnd : 18
	readonly property var calendarIconSun: settings.calendarIconSun !== undefined ? settings.calendarIconSun : "\uf522"
	readonly property var calendarIconMoon: settings.calendarIconMoon !== undefined ? settings.calendarIconMoon : "\ue3a4"
	readonly property var calendarBirthYear: settings.calendarBirthYear !== undefined ? settings.calendarBirthYear : 0
	readonly property var calendarLifeExpectancy: settings.calendarLifeExpectancy !== undefined ? settings.calendarLifeExpectancy : 90
	readonly property var calendarOutside: settings.calendarOutside !== undefined ? settings.calendarOutside : "#4f4f4f"

	// weather card and its code table
	readonly property var weatherLocation: settings.weatherLocation !== undefined ? settings.weatherLocation : ""
	readonly property var weatherCoords: settings.weatherCoords !== undefined ? settings.weatherCoords : ""
	readonly property var weatherPlaceCount: settings.weatherPlaceCount !== undefined ? settings.weatherPlaceCount : 4
	readonly property var weatherPlaceDefaults: settings.weatherPlaceDefaults !== undefined ? settings.weatherPlaceDefaults : ["San Francisco", "Miami"]
	readonly property var weatherStationCount: settings.weatherStationCount !== undefined ? settings.weatherStationCount : 3
	readonly property var weatherRefreshMs: settings.weatherRefreshMs !== undefined ? settings.weatherRefreshMs : 120000
	readonly property var weatherRetryMs: settings.weatherRetryMs !== undefined ? settings.weatherRetryMs : 5000
	readonly property var weatherCacheMs: settings.weatherCacheMs !== undefined ? settings.weatherCacheMs : 120000
	readonly property var weatherIcon: settings.weatherIcon !== undefined ? settings.weatherIcon : "\udb83\udf2f"
	readonly property var weatherLoadingIcon: settings.weatherLoadingIcon !== undefined ? settings.weatherLoadingIcon : "\udb86\udcf6"
	readonly property var weatherBase: settings.weatherBase !== undefined ? settings.weatherBase : "#7cc4f0"
	readonly property var weatherBaseMono: settings.weatherBaseMono !== undefined ? settings.weatherBaseMono : "#ffffff"
	readonly property var weatherTempUnit: settings.weatherTempUnit !== undefined ? settings.weatherTempUnit : "fahrenheit"
	readonly property var weatherWindUnit: settings.weatherWindUnit !== undefined ? settings.weatherWindUnit : "mph"
	readonly property var weatherDays: settings.weatherDays !== undefined ? settings.weatherDays : 7
	readonly property var weatherCardWidth: settings.weatherCardWidth !== undefined ? settings.weatherCardWidth : 470
	readonly property var weatherCardPadding: settings.weatherCardPadding !== undefined ? settings.weatherCardPadding : 18
	readonly property var weatherCardGap: settings.weatherCardGap !== undefined ? settings.weatherCardGap : 16
	readonly property var weatherCardHeaderGap: settings.weatherCardHeaderGap !== undefined ? settings.weatherCardHeaderGap : 12
	readonly property var weatherHeroGlyphSize: settings.weatherHeroGlyphSize !== undefined ? settings.weatherHeroGlyphSize : 54
	readonly property var weatherHeroTempSize: settings.weatherHeroTempSize !== undefined ? settings.weatherHeroTempSize : 52
	readonly property var weatherHeroUnitSize: settings.weatherHeroUnitSize !== undefined ? settings.weatherHeroUnitSize : 19
	readonly property var weatherHeroUnitTop: settings.weatherHeroUnitTop !== undefined ? settings.weatherHeroUnitTop : 4
	readonly property var weatherHeroLabelSize: settings.weatherHeroLabelSize !== undefined ? settings.weatherHeroLabelSize : 11
	readonly property var weatherHeroValueSize: settings.weatherHeroValueSize !== undefined ? settings.weatherHeroValueSize : 19
	readonly property var weatherDayGlyphSize: settings.weatherDayGlyphSize !== undefined ? settings.weatherDayGlyphSize : 30
	readonly property var weatherDayLabelSize: settings.weatherDayLabelSize !== undefined ? settings.weatherDayLabelSize : 12
	readonly property var weatherDayTempSize: settings.weatherDayTempSize !== undefined ? settings.weatherDayTempSize : 17
	readonly property var weatherDayGap: settings.weatherDayGap !== undefined ? settings.weatherDayGap : 10
	readonly property var weatherPlaceSize: settings.weatherPlaceSize !== undefined ? settings.weatherPlaceSize : 13
	readonly property var weatherActionSize: settings.weatherActionSize !== undefined ? settings.weatherActionSize : 12
	readonly property var weatherIconLeft: settings.weatherIconLeft !== undefined ? settings.weatherIconLeft : "\uf104"
	readonly property var weatherIconRight: settings.weatherIconRight !== undefined ? settings.weatherIconRight : "\uf105"
	readonly property var weatherIconAdd: settings.weatherIconAdd !== undefined ? settings.weatherIconAdd : "\uf067"
	readonly property var weatherSeparator: settings.weatherSeparator !== undefined ? settings.weatherSeparator : 1
	readonly property var weatherSeparatorColor: settings.weatherSeparatorColor !== undefined ? settings.weatherSeparatorColor : "#2b2b2b"
	readonly property var weatherCardSearchDebounce: settings.weatherCardSearchDebounce !== undefined ? settings.weatherCardSearchDebounce : 60
	readonly property var weatherCodes: settings.weatherCodes !== undefined ? settings.weatherCodes : [
		{ code: 0, name: "Clear", glyph: "\udb81\udd99" },
		{ code: 1, name: "Mainly clear", glyph: "\udb81\udd95" },
		{ code: 2, name: "Partly cloudy", glyph: "\udb81\udd95" },
		{ code: 3, name: "Overcast", glyph: "\udb81\udd90" },
		{ code: 45, name: "Fog", glyph: "\udb81\udd91" },
		{ code: 48, name: "Freezing fog", glyph: "\udb81\udd91" },
		{ code: 51, name: "Light drizzle", glyph: "\udb83\udf33" },
		{ code: 53, name: "Drizzle", glyph: "\udb81\udd97" },
		{ code: 55, name: "Dense drizzle", glyph: "\udb81\udd97" },
		{ code: 56, name: "Freezing drizzle", glyph: "\udb81\ude7f" },
		{ code: 57, name: "Freezing drizzle", glyph: "\udb81\ude7f" },
		{ code: 61, name: "Light rain", glyph: "\udb81\udd97" },
		{ code: 63, name: "Rain", glyph: "\udb81\udd97" },
		{ code: 65, name: "Heavy rain", glyph: "\udb81\udd96" },
		{ code: 66, name: "Freezing rain", glyph: "\udb81\ude7f" },
		{ code: 67, name: "Freezing rain", glyph: "\udb81\ude7f" },
		{ code: 71, name: "Light snow", glyph: "\udb81\udd98" },
		{ code: 73, name: "Snow", glyph: "\udb81\udd98" },
		{ code: 75, name: "Heavy snow", glyph: "\udb83\udf36" },
		{ code: 77, name: "Snow grains", glyph: "\udb81\udd98" },
		{ code: 80, name: "Light showers", glyph: "\udb83\udf33" },
		{ code: 81, name: "Rain showers", glyph: "\udb81\udd97" },
		{ code: 82, name: "Violent showers", glyph: "\udb81\udd96" },
		{ code: 85, name: "Snow showers", glyph: "\udb83\udf34" },
		{ code: 86, name: "Heavy snow showers", glyph: "\udb83\udf36" },
		{ code: 95, name: "Thunderstorm", glyph: "\udb81\udd93" },
		{ code: 96, name: "Storm with hail", glyph: "\udb81\ude7e" },
		{ code: 99, name: "Storm with hail", glyph: "\udb81\ude7e" }
	]

	// notification toasts
	readonly property var notifyBase: settings.notifyBase !== undefined ? settings.notifyBase : "#ffffff"
	readonly property var notifyScale: settings.notifyScale !== undefined ? settings.notifyScale : 1.25
	readonly property var notifyWidth: settings.notifyWidth !== undefined ? settings.notifyWidth : 350
	readonly property var notifyPadding: settings.notifyPadding !== undefined ? settings.notifyPadding : 15
	readonly property var notifyPaddingY: settings.notifyPaddingY !== undefined ? settings.notifyPaddingY : 0
	readonly property var notifyRowHeight: settings.notifyRowHeight !== undefined ? settings.notifyRowHeight : 48
	readonly property var notifyRowPadding: settings.notifyRowPadding !== undefined ? settings.notifyRowPadding : 3
	readonly property var notifySlot: settings.notifySlot !== undefined ? settings.notifySlot : 33
	readonly property var notifySlotGap: settings.notifySlotGap !== undefined ? settings.notifySlotGap : 13
	readonly property var notifyBellSize: settings.notifyBellSize !== undefined ? settings.notifyBellSize : 30
	readonly property var notifyAppFontSize: settings.notifyAppFontSize !== undefined ? settings.notifyAppFontSize : 14
	readonly property var notifyVisibleRows: settings.notifyVisibleRows !== undefined ? settings.notifyVisibleRows : 5
	readonly property var notifyHistory: settings.notifyHistory !== undefined ? settings.notifyHistory : 50
	readonly property var notifyGoneOpacity: settings.notifyGoneOpacity !== undefined ? settings.notifyGoneOpacity : 0.55
	readonly property var notifyEmpty: settings.notifyEmpty !== undefined ? settings.notifyEmpty : "Nothing yet"
	readonly property var notifyTitle: settings.notifyTitle !== undefined ? settings.notifyTitle : "Notifications"
	readonly property var notifyRowGap: settings.notifyRowGap !== undefined ? settings.notifyRowGap : 6
	readonly property var notifySeparator: settings.notifySeparator !== undefined ? settings.notifySeparator : 1
	readonly property var notifySeparatorColor: settings.notifySeparatorColor !== undefined ? settings.notifySeparatorColor : "#3f3f3f"
	readonly property var notifyImageMax: settings.notifyImageMax !== undefined ? settings.notifyImageMax : 140
	readonly property var notifySweepWidth: settings.notifySweepWidth !== undefined ? settings.notifySweepWidth : 30
	readonly property var notifyTimeout: settings.notifyTimeout !== undefined ? settings.notifyTimeout : 6000
	readonly property var notifyDismissKey: settings.notifyDismissKey !== undefined ? settings.notifyDismissKey : "d"
	readonly property var notifyClearKey: settings.notifyClearKey !== undefined ? settings.notifyClearKey : "x"

	// contribution graph
	readonly property var contribBase: settings.contribBase !== undefined ? settings.contribBase : "#7bd88f"
	readonly property var contribBaseMono: settings.contribBaseMono !== undefined ? settings.contribBaseMono : "#ffffff"
	readonly property var contribEmpty: settings.contribEmpty !== undefined ? settings.contribEmpty : "#1f1f1f"
	readonly property var contribWeeks: settings.contribWeeks !== undefined ? settings.contribWeeks : 19
	readonly property var contribCell: settings.contribCell !== undefined ? settings.contribCell : 10
	readonly property var contribGap: settings.contribGap !== undefined ? settings.contribGap : 3
	readonly property var contribCacheMs: settings.contribCacheMs !== undefined ? settings.contribCacheMs : 21600000
	readonly property var contribUser: settings.contribUser !== undefined ? settings.contribUser : ""
	readonly property var contribTooltipWidth: settings.contribTooltipWidth !== undefined ? settings.contribTooltipWidth : 244
	readonly property var contribTooltipPadding: settings.contribTooltipPadding !== undefined ? settings.contribTooltipPadding : 12
	readonly property var contribAvatar: settings.contribAvatar !== undefined ? settings.contribAvatar : 24

	// display panel
	readonly property var displayFile: settings.displayFile !== undefined ? settings.displayFile : "cache/display.lua"
	readonly property var displayBase: settings.displayBase !== undefined ? settings.displayBase : "#7aa2f7"
	readonly property var displayBaseMono: settings.displayBaseMono !== undefined ? settings.displayBaseMono : "#ffffff"
	readonly property var displayPanelWidth: settings.displayPanelWidth !== undefined ? settings.displayPanelWidth : 296
	readonly property var displayPanelPadding: settings.displayPanelPadding !== undefined ? settings.displayPanelPadding : 12
	readonly property var displayRowHeight: settings.displayRowHeight !== undefined ? settings.displayRowHeight : 18
	readonly property var displayRowGap: settings.displayRowGap !== undefined ? settings.displayRowGap : 3
	readonly property var displayGroupGap: settings.displayGroupGap !== undefined ? settings.displayGroupGap : 10
	readonly property var displayLabelSize: settings.displayLabelSize !== undefined ? settings.displayLabelSize : 10
	readonly property var displayDetailSize: settings.displayDetailSize !== undefined ? settings.displayDetailSize : 10
	readonly property var displayDetailGap: settings.displayDetailGap !== undefined ? settings.displayDetailGap : 3
	readonly property var displayValueGap: settings.displayValueGap !== undefined ? settings.displayValueGap : 6
	readonly property var stepBarHeight: settings.stepBarHeight !== undefined ? settings.stepBarHeight : 6
	readonly property var stepBarGap: settings.stepBarGap !== undefined ? settings.stepBarGap : 2
	readonly property var displaySeparatorColor: settings.displaySeparatorColor !== undefined ? settings.displaySeparatorColor : "#3f3f3f"
	readonly property var displaySeparatorHeight: settings.displaySeparatorHeight !== undefined ? settings.displaySeparatorHeight : 1
	readonly property var displayScaleMin: settings.displayScaleMin !== undefined ? settings.displayScaleMin : 1
	readonly property var displayScaleMax: settings.displayScaleMax !== undefined ? settings.displayScaleMax : 2
	readonly property var displayFonts: settings.displayFonts !== undefined ? settings.displayFonts : [10, 11, 12, 13, 14, 16, 18]
	readonly property var displayResolutionLimit: settings.displayResolutionLimit !== undefined ? settings.displayResolutionLimit : 6
	readonly property var displayTitle: settings.displayTitle !== undefined ? settings.displayTitle : "Display"
	readonly property var displayResolutionTitle: settings.displayResolutionTitle !== undefined ? settings.displayResolutionTitle : "Resolution"
	readonly property var displayRefreshTitle: settings.displayRefreshTitle !== undefined ? settings.displayRefreshTitle : "Refresh"
	readonly property var displayScaleTitle: settings.displayScaleTitle !== undefined ? settings.displayScaleTitle : "Scale"
	readonly property var displayFontTitle: settings.displayFontTitle !== undefined ? settings.displayFontTitle : "Font"
	readonly property var displayNothing: settings.displayNothing !== undefined ? settings.displayNothing : "No display found"
	readonly property var displayIconRefresh: settings.displayIconRefresh !== undefined ? settings.displayIconRefresh : "\uf021"

	// network and speed test
	readonly property var networkBase: settings.networkBase !== undefined ? settings.networkBase : "#61afef"
	readonly property var networkBaseMono: settings.networkBaseMono !== undefined ? settings.networkBaseMono : "#ffffff"
	readonly property var networkDown: settings.networkDown !== undefined ? settings.networkDown : "#7bd88f"
	readonly property var networkDownMono: settings.networkDownMono !== undefined ? settings.networkDownMono : "#ffffff"
	readonly property var networkUp: settings.networkUp !== undefined ? settings.networkUp : "#e06c9f"
	readonly property var networkUpMono: settings.networkUpMono !== undefined ? settings.networkUpMono : "#9a9a9a"
	readonly property var networkIdle: settings.networkIdle !== undefined ? settings.networkIdle : "#2f2f2f"
	readonly property var networkPollMs: settings.networkPollMs !== undefined ? settings.networkPollMs : 1000
	readonly property var networkHistory: settings.networkHistory !== undefined ? settings.networkHistory : 60
	readonly property var networkGraphHeight: settings.networkGraphHeight !== undefined ? settings.networkGraphHeight : 40
	readonly property var networkGraphFontSize: settings.networkGraphFontSize !== undefined ? settings.networkGraphFontSize : 16.666666666666668
	readonly property var networkGraphGap: settings.networkGraphGap !== undefined ? settings.networkGraphGap : 2
	readonly property var networkTooltipWidth: settings.networkTooltipWidth !== undefined ? settings.networkTooltipWidth : 260
	readonly property var networkTooltipPadding: settings.networkTooltipPadding !== undefined ? settings.networkTooltipPadding : 12
	readonly property var networkRowHeight: settings.networkRowHeight !== undefined ? settings.networkRowHeight : 18
	readonly property var networkRowGap: settings.networkRowGap !== undefined ? settings.networkRowGap : 3
	readonly property var networkBarCount: settings.networkBarCount !== undefined ? settings.networkBarCount : 4
	readonly property var networkBarWidth: settings.networkBarWidth !== undefined ? settings.networkBarWidth : 3
	readonly property var networkBarGap: settings.networkBarGap !== undefined ? settings.networkBarGap : 2
	readonly property var networkBarStep: settings.networkBarStep !== undefined ? settings.networkBarStep : 3
	readonly property var networkBarsInk: settings.networkBarsInk !== undefined ? settings.networkBarsInk : "#ffffff"
	readonly property var networkBarsOff: settings.networkBarsOff !== undefined ? settings.networkBarsOff : "#2f2f2f"
	readonly property var networkSpeedCancelKey: settings.networkSpeedCancelKey !== undefined ? settings.networkSpeedCancelKey : "k"
	readonly property var networkSpeedNone: settings.networkSpeedNone !== undefined ? settings.networkSpeedNone : "Run a speed test"
	readonly property var networkSpeedUnit: settings.networkSpeedUnit !== undefined ? settings.networkSpeedUnit : "Mbps"
	readonly property var networkSpeedTestingDown: settings.networkSpeedTestingDown !== undefined ? settings.networkSpeedTestingDown : "Testing download speed\u2026"
	readonly property var networkSpeedTestingUp: settings.networkSpeedTestingUp !== undefined ? settings.networkSpeedTestingUp : "Testing upload speed\u2026"
	readonly property var networkSpeedAgain: settings.networkSpeedAgain !== undefined ? settings.networkSpeedAgain : "Enter to try again"
	readonly property var speedGaugeSize: settings.speedGaugeSize !== undefined ? settings.speedGaugeSize : 160
	readonly property var speedRingSegs: settings.speedRingSegs !== undefined ? settings.speedRingSegs : 44
	readonly property var speedRingWidth: settings.speedRingWidth !== undefined ? settings.speedRingWidth : 9
	readonly property var speedRingGap: settings.speedRingGap !== undefined ? settings.speedRingGap : 3
	readonly property var speedValueSize: settings.speedValueSize !== undefined ? settings.speedValueSize : 36
	readonly property var speedUnitSize: settings.speedUnitSize !== undefined ? settings.speedUnitSize : 12
	readonly property var speedArrowSize: settings.speedArrowSize !== undefined ? settings.speedArrowSize : 16
	readonly property var speedArrowGap: settings.speedArrowGap !== undefined ? settings.speedArrowGap : 6
	readonly property var speedNeedleBase: settings.speedNeedleBase !== undefined ? settings.speedNeedleBase : 40
	readonly property var speedNeedleLen: settings.speedNeedleLen !== undefined ? settings.speedNeedleLen : 22
	readonly property var speedNeedleWidth: settings.speedNeedleWidth !== undefined ? settings.speedNeedleWidth : 2
	readonly property var speedButtonPadX: settings.speedButtonPadX !== undefined ? settings.speedButtonPadX : 10
	readonly property var speedButtonPadY: settings.speedButtonPadY !== undefined ? settings.speedButtonPadY : 4
	readonly property var networkTitle: settings.networkTitle !== undefined ? settings.networkTitle : "Network"
	readonly property var networkScanTitle: settings.networkScanTitle !== undefined ? settings.networkScanTitle : "Wi-Fi"
	readonly property var networkWifiNothing: settings.networkWifiNothing !== undefined ? settings.networkWifiNothing : "No networks found"
	readonly property var networkWiredNothing: settings.networkWiredNothing !== undefined ? settings.networkWiredNothing : "No connection"
	readonly property var networkPasswordHint: settings.networkPasswordHint !== undefined ? settings.networkPasswordHint : "Password"
	readonly property var networkForget: settings.networkForget !== undefined ? settings.networkForget : "Forget"
	readonly property var networkConnect: settings.networkConnect !== undefined ? settings.networkConnect : "Connect"
	readonly property var networkScanIcon: settings.networkScanIcon !== undefined ? settings.networkScanIcon : "\uf021"
	readonly property var networkWifiIcons: settings.networkWifiIcons !== undefined ? settings.networkWifiIcons : ["\udb82\udcbc", "\udb82\udcbd", "\udb82\udcbe", "\udb82\udcbf"]
	readonly property var networkLanIcon: settings.networkLanIcon !== undefined ? settings.networkLanIcon : "\udb80\ude00"
	readonly property var networkLockIcon: settings.networkLockIcon !== undefined ? settings.networkLockIcon : "\uf023"

	// agent panel
	readonly property var agentFaceSize: settings.agentFaceSize !== undefined ? settings.agentFaceSize : 96
	readonly property var agentMorphMs: settings.agentMorphMs !== undefined ? settings.agentMorphMs : 420
	readonly property var agentSpinMs: settings.agentSpinMs !== undefined ? settings.agentSpinMs : 120000
	readonly property var agentDoneWidth: settings.agentDoneWidth !== undefined ? settings.agentDoneWidth : 230
	readonly property var agentColumnWidth: settings.agentColumnWidth !== undefined ? settings.agentColumnWidth : 230
	readonly property var agentPlanWidth: settings.agentPlanWidth !== undefined ? settings.agentPlanWidth : 240
	readonly property var agentPanelWidth: settings.agentPanelWidth !== undefined ? settings.agentPanelWidth : 742
	readonly property var agentPanelHeight: settings.agentPanelHeight !== undefined ? settings.agentPanelHeight : 398
	readonly property var agentPanelPadding: settings.agentPanelPadding !== undefined ? settings.agentPanelPadding : 12
	readonly property var agentIdleText: settings.agentIdleText !== undefined ? settings.agentIdleText : "Idle"
	readonly property var agentWorkingText: settings.agentWorkingText !== undefined ? settings.agentWorkingText : "Working"
	readonly property var agentBlockedText: settings.agentBlockedText !== undefined ? settings.agentBlockedText : "a session needs attention"
	readonly property var agentErrorText: settings.agentErrorText !== undefined ? settings.agentErrorText : "Error"
	readonly property var agentPanelTitle: settings.agentPanelTitle !== undefined ? settings.agentPanelTitle : "Agent"
	readonly property var agentNameFile: settings.agentNameFile !== undefined ? settings.agentNameFile : "cache/agent-name"
	readonly property var agentDoneTitle: settings.agentDoneTitle !== undefined ? settings.agentDoneTitle : "Done"
	readonly property var agentIconQuestion: settings.agentIconQuestion !== undefined ? settings.agentIconQuestion : "?"
	readonly property var agentIconDone: settings.agentIconDone !== undefined ? settings.agentIconDone : "\uf00c"
	readonly property var agentIconClose: settings.agentIconClose !== undefined ? settings.agentIconClose : "\uf00d"
	readonly property var agentPlanTitle: settings.agentPlanTitle !== undefined ? settings.agentPlanTitle : "Subscription"
	readonly property var agentPlanName: settings.agentPlanName !== undefined ? settings.agentPlanName : "OpenCode Go"
	readonly property var agentPlanIcon: settings.agentPlanIcon !== undefined ? settings.agentPlanIcon : "opencode"
}
