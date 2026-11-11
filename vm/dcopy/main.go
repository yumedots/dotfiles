package main

import (
	"fmt"
	"io"
	"os"
	"strconv"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: dcopy src dst offset")
		os.Exit(2)
	}
	offset := int64(0)
	if len(os.Args) > 3 {
		offset, _ = strconv.ParseInt(os.Args[3], 10, 64)
	}
	src, err := os.Open(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer src.Close()
	dst, err := os.OpenFile(os.Args[2], os.O_WRONLY, 0)
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
	size := info.Size()
	for off := int64(0); off < size; {
		data, err := src.Seek(off, 3)
		if err != nil {
			if err == io.EOF {
				break
			}
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		hole, err := src.Seek(data, 4)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if hole > size {
			hole = size
		}
		if _, err := src.Seek(data, 0); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if _, err := dst.Seek(offset+data, 0); err != nil {
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
