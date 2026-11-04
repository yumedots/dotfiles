#!/usr/bin/env python3
import select
import struct
import sys
import time

keyboard = open(sys.argv[1], "rb", buffering=0)
tablet = open(sys.argv[2], "rb", buffering=0)
tty = open("/dev/ttyS0", "wb", buffering=0)
last_mouse = 0.0

while True:
    ready, _, _ = select.select([keyboard, tablet], [], [], 1)
    for fd in ready:
        data = fd.read(24)
        if len(data) < 24:
            continue
        _, _, kind, code, value = struct.unpack("@qqHHi", data)
        if fd is keyboard and kind == 1 and code == 30 and value == 1:
            tty.write(b"YUDAE_K\n")
        elif fd is tablet and kind == 3 and code == 0 and value > 0:
            now = time.monotonic()
            if now - last_mouse > 0.1:
                last_mouse = now
                tty.write(b"YUDAE_M\n")
