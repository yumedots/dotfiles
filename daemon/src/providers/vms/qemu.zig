const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Config = struct {
	name: []const u8,
	dir: []const u8,
	disk: []const u8,
	dotfiles: []const u8,
	cores: u32,
	mem_mb: u32,
	cid: u32,
	gl: bool,
	view: bool = true,
};

pub fn args(allocator: Allocator, config: Config) ![]const []const u8 {
	var list: std.ArrayList([]const u8) = .empty;

	const qmp = try std.fs.path.join(allocator, &.{ config.dir, "qmp.sock" });
	const serial = try std.fs.path.join(allocator, &.{ config.dir, "serial.log" });
	const vfs = try std.fs.path.join(allocator, &.{ config.dir, "virtiofsd.sock" });

	try list.append(allocator, "qemu-system-x86_64");
	try addPair(allocator, &list, "-name", try std.fmt.allocPrint(allocator, "yudae-{s}", .{config.name}));
	try addPair(allocator, &list, "-machine", "q35,accel=kvm");
	try list.append(allocator, "-nodefaults");
	try addPair(allocator, &list, "-cpu", "host");
	try addPair(allocator, &list, "-smp", try std.fmt.allocPrint(allocator, "{d}", .{config.cores}));
	try addPair(allocator, &list, "-m", try std.fmt.allocPrint(allocator, "{d}M", .{config.mem_mb}));
	try addPair(allocator, &list, "-object", try std.fmt.allocPrint(allocator, "memory-backend-memfd,id=mem,size={d}M,share=on", .{config.mem_mb}));
	try addPair(allocator, &list, "-numa", "node,memdev=mem");
	try addPair(allocator, &list, "-drive", try std.fmt.allocPrint(allocator, "file={s},if=virtio,format=qcow2,cache=none,aio=io_uring", .{config.disk}));

	const xres: u32 = if (config.view) 2560 else 1280;
	const yres: u32 = if (config.view) 1440 else 720;

	if (config.gl) {
		try addPair(allocator, &list, "-device", try std.fmt.allocPrint(allocator, "virtio-gpu-gl-pci,xres={d},yres={d},max_outputs=1", .{ xres, yres }));
	} else {
		try addPair(allocator, &list, "-device", try std.fmt.allocPrint(allocator, "virtio-gpu-pci,xres={d},yres={d},max_outputs=1", .{ xres, yres }));
	}

	try addPair(allocator, &list, "-device", "virtio-balloon-pci,free-page-reporting=on");
	try addPair(allocator, &list, "-device", try std.fmt.allocPrint(allocator, "vhost-vsock-pci,guest-cid={d}", .{config.cid}));
	try addPair(allocator, &list, "-chardev", try std.fmt.allocPrint(allocator, "socket,id=vfs0,path={s}", .{vfs}));
	try addPair(allocator, &list, "-device", "vhost-user-fs-pci,chardev=vfs0,tag=dotfiles");
	try addPair(allocator, &list, "-vga", "none");
	try addPair(allocator, &list, "-device", "virtio-rng-pci");
	try addPair(allocator, &list, "-device", "virtio-tablet-pci");
	try addPair(allocator, &list, "-device", "virtio-keyboard-pci");
	try addPair(allocator, &list, "-netdev", "user,id=net0");
	try addPair(allocator, &list, "-device", "virtio-net-pci,netdev=net0");
	try addPair(allocator, &list, "-qmp", try std.fmt.allocPrint(allocator, "unix:{s},server=on,wait=off", .{qmp}));
	try addPair(allocator, &list, "-serial", try std.fmt.allocPrint(allocator, "file:{s}", .{serial}));
	try addPair(allocator, &list, "-monitor", "none");
	if (config.view) {
		try addPair(allocator, &list, "-display", "gtk,gl=on,grab-on-hover=on,full-screen=on,show-cursor=on");
	} else {
		try addPair(allocator, &list, "-display", "egl-headless");
	}
	try list.append(allocator, "-no-reboot");

	return list.toOwnedSlice(allocator);
}

fn addPair(allocator: Allocator, list: *std.ArrayList([]const u8), flag: []const u8, value: []const u8) !void {
	try list.append(allocator, flag);
	try list.append(allocator, value);
}
