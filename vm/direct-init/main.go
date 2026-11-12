package main

import (
	"fmt"
	"os"
	"strings"
	"syscall"
	"unsafe"
)

var zero [1]byte

const sysFinitModule = 313

func mount(source, target, fstype string, flags uintptr, data string) error {
	if err := os.MkdirAll(target, 0o755); err != nil {
		return err
	}
	if err := syscall.Mount(source, target, fstype, flags, data); err != nil {
		return fmt.Errorf("mount %s on %s: %w", source, target, err)
	}
	return nil
}

func load(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()

	_, _, errno := syscall.Syscall(sysFinitModule, file.Fd(), uintptr(unsafe.Pointer(&zero[0])), 0)
	if errno != 0 && errno != syscall.EEXIST {
		return fmt.Errorf("load %s: %w", path, errno)
	}
	return nil
}

func modules() {
	for _, name := range []string{"fat", "vfat", "failover", "net_failover", "virtio_net", "netfs", "9pnet", "9p", "9pnet_virtio"} {
		if err := load("/modules/" + name + ".ko"); err != nil {
			fmt.Println(err)
		}
	}
}

func main() {
	os.MkdirAll("/proc", 0o755)
	os.MkdirAll("/sys", 0o755)
	os.MkdirAll("/dev", 0o755)
	if err := mount("proc", "/proc", "proc", 0, ""); err != nil {
		fmt.Println(err)
	}
	if err := mount("sysfs", "/sys", "sysfs", 0, ""); err != nil {
		fmt.Println(err)
	}
	if err := mount("devtmpfs", "/dev", "devtmpfs", 0, ""); err != nil {
		fmt.Println(err)
	}

	modules()

	if err := mount("/dev/vda3", "/newroot", "btrfs", 0, ""); err != nil {
		fmt.Println(err)
		syscall.Exec("/bin/sh", []string{"sh"}, os.Environ())
	}

	for _, dir := range []string{"/newroot/proc", "/newroot/sys", "/newroot/dev", "/newroot/mnt/seed", "/newroot/mnt/hostpkg"} {
		os.MkdirAll(dir, 0o755)
	}
	if err := mount("proc", "/newroot/proc", "proc", 0, ""); err != nil {
		fmt.Println(err)
	}
	if err := mount("sysfs", "/newroot/sys", "sysfs", 0, ""); err != nil {
		fmt.Println(err)
	}
	if err := mount("devtmpfs", "/newroot/dev", "devtmpfs", 0, ""); err != nil {
		fmt.Println(err)
	}
	if err := mount("/dev/vdb", "/newroot/mnt/seed", "vfat", syscall.MS_RDONLY, ""); err != nil {
		fmt.Println(err)
	}
	if err := mount("hostpkg", "/newroot/mnt/hostpkg", "9p", 0, "trans=virtio,version=9p2000.L"); err != nil {
		fmt.Println(err)
	}

	if err := syscall.Chroot("/newroot"); err != nil {
		fmt.Println(err)
		syscall.Exec("/bin/sh", []string{"sh"}, os.Environ())
	}
	os.Chdir("/")
	env := []string{"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "HOME=/root", "TERM=linux"}
	if data, err := os.ReadFile("/proc/cmdline"); err == nil && strings.Contains(string(data), "dotfiles.parallel=1") {
		if err := syscall.Exec("/bin/bash", []string{"bash", "/mnt/seed/boot.sh"}, env); err != nil {
			fmt.Println(err)
		}
	}
	os.MkdirAll("/etc/systemd/system", 0o755)
	for _, name := range []string{"provision.service", "provision.target"} {
		data, err := os.ReadFile("/mnt/seed/" + name)
		if err == nil {
			os.WriteFile("/etc/systemd/system/"+name, data, 0o644)
		}
	}
	if err := syscall.Exec("/sbin/init", []string{"systemd"}, env); err != nil {
		fmt.Println(err)
	}
}
