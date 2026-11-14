const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Config = struct {
	name: []const u8,
	dir: []const u8,
	disk: []const u8,
	dotfiles: []const u8,
	wallpaper_dir: []const u8 = "",
	cores: u32,
	mem_mb: u32,
	cid: u32,
	gl: bool,
};

pub fn args(allocator: Allocator, config: Config) ![]const []const u8 {
	var list: std.ArrayList([]const u8) = .empty;

	const qmp = try std.fs.path.join(allocator, &.{ config.dir, "qmp.sock" });
	const display_qmp = try std.fs.path.join(allocator, &.{ config.dir, "display.qmp" });
	const serial = try std.fs.path.join(allocator, &.{ config.dir, "serial.log" });
	const vfs = try std.fs.path.join(allocator, &.{ config.dir, "virtiofsd.sock" });
	const wall = try std.fs.path.join(allocator, &.{ config.dir, "wallpaper.sock" });

	const binary = blk: {
		if (std.c.getenv("YUDAE_QEMU")) |value| break :blk std.mem.span(value);
		const home = if (std.c.getenv("HOME")) |value| std.mem.span(value) else break :blk "qemu-system-x86_64";
		const path = std.fmt.allocPrint(allocator, "{s}/qemu-linux/install/bin/qemu-system-x86_64", .{home}) catch break :blk "qemu-system-x86_64";
		break :blk path;
	};
	try list.append(allocator, binary);
	try addPair(allocator, &list, "-name", try std.fmt.allocPrint(allocator, "yudae-{s}", .{config.name}));
	try addPair(allocator, &list, "-machine", "q35,accel=kvm");
	try addPair(allocator, &list, "-rtc", "base=utc,clock=host");
	try list.append(allocator, "-nodefaults");
	try addPair(allocator, &list, "-cpu", "host");
	try addPair(allocator, &list, "-smp", try std.fmt.allocPrint(allocator, "{d}", .{config.cores}));
	try addPair(allocator, &list, "-m", try std.fmt.allocPrint(allocator, "{d}M", .{config.mem_mb}));
	try addPair(allocator, &list, "-object", try std.fmt.allocPrint(allocator, "memory-backend-memfd,id=mem,size={d}M,share=on", .{config.mem_mb}));
	try addPair(allocator, &list, "-numa", "node,memdev=mem");
	try addPair(allocator, &list, "-drive", try std.fmt.allocPrint(allocator, "file={s},if=virtio,format=qcow2,cache=none,aio=io_uring", .{config.disk}));

	if (config.gl) {
		try addPair(allocator, &list, "-device", "virtio-gpu-gl-pci,xres=2560,yres=1440,max_outputs=1");
	} else {
		try addPair(allocator, &list, "-device", "virtio-gpu-pci,xres=2560,yres=1440,max_outputs=1");
	}

	try addPair(allocator, &list, "-device", "virtio-balloon-pci,free-page-reporting=on");
	try addPair(allocator, &list, "-device", try std.fmt.allocPrint(allocator, "vhost-vsock-pci,guest-cid={d}", .{config.cid}));
	try addPair(allocator, &list, "-chardev", try std.fmt.allocPrint(allocator, "socket,id=vfs0,path={s}", .{vfs}));
	try addPair(allocator, &list, "-device", "vhost-user-fs-pci,chardev=vfs0,tag=dotfiles");

	if (config.wallpaper_dir.len > 0) {
		try addPair(allocator, &list, "-chardev", try std.fmt.allocPrint(allocator, "socket,id=wall0,path={s}", .{wall}));
		try addPair(allocator, &list, "-device", "vhost-user-fs-pci,chardev=wall0,tag=wallpaper");
	}
	try addPair(allocator, &list, "-vga", "none");
	try addPair(allocator, &list, "-device", "virtio-rng-pci");
	try addPair(allocator, &list, "-device", "virtio-tablet-pci");
	try addPair(allocator, &list, "-device", "virtio-keyboard-pci");
	try addPair(allocator, &list, "-netdev", "user,id=net0");
	try addPair(allocator, &list, "-device", "virtio-net-pci,netdev=net0");
	try addPair(allocator, &list, "-qmp", try std.fmt.allocPrint(allocator, "unix:{s},server=on,wait=off", .{qmp}));
	try addPair(allocator, &list, "-qmp", try std.fmt.allocPrint(allocator, "unix:{s},server=on,wait=off", .{display_qmp}));
	try addPair(allocator, &list, "-serial", try std.fmt.allocPrint(allocator, "file:{s}", .{serial}));
	try addPair(allocator, &list, "-monitor", "none");
	try addPair(allocator, &list, "-display", if (config.gl) "dbus,p2p=yes,gl=on" else "dbus,p2p=yes");
	try list.append(allocator, "-no-reboot");

	return list.toOwnedSlice(allocator);
}

fn addPair(allocator: Allocator, list: *std.ArrayList([]const u8), flag: []const u8, value: []const u8) !void {
	try list.append(allocator, flag);
	try list.append(allocator, value);
}
