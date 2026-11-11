package main

import (
	"fmt"
	"io"
	"os"
	"strconv"
)

func main() {
	if len(os.Args) < 4 {
		fmt.Fprintln(os.Stderr, "usage: dcopy src dst dst_offset [src_offset] [length]")
		os.Exit(2)
	}
	dstOffset, err := strconv.ParseInt(os.Args[3], 10, 64)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	srcOffset := int64(0)
	if len(os.Args) > 4 {
		srcOffset, _ = strconv.ParseInt(os.Args[4], 10, 64)
	}
	src, err := os.Open(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer src.Close()
	dst, err := os.OpenFile(os.Args[2], os.O_WRONLY|os.O_CREATE, 0o644)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer dst.Close()
	info, err := src.Stat()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	end := info.Size()
	if len(os.Args) > 5 {
		length, _ := strconv.ParseInt(os.Args[5], 10, 64)
		if length > 0 && srcOffset+length < end {
			end = srcOffset + length
		}
	}
	for off := srcOffset; off < end; {
		data, err := src.Seek(off, 3)
		if err != nil {
			if err == io.EOF {
				break
			}
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if data >= end {
			break
		}
		hole, err := src.Seek(data, 4)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if hole > end {
			hole = end
		}
		if _, err := src.Seek(data, 0); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if _, err := dst.Seek(dstOffset+data-srcOffset, 0); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if _, err := io.CopyN(dst, src, hole-data); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		off = hole
	}
}
