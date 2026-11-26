#!/usr/bin/env python3
"""Root-relative pointer warp: warp.py X Y

xdotool's `mousemove` goes through the XTEST extension, which Xephyr (kdrive)
confines to the sub-screen the pointer is currently on: a cross-monitor move
clamps at the Xinerama boundary, no crossing events are delivered, and a
window manager under test never sees the pointer arrive. A direct
XWarpPointer to the root window travels the whole merged screen, so the
functional tests move the pointer through this helper (python3 + ctypes +
libX11, nothing to install)."""
import ctypes
import ctypes.util
import os
import sys

if len(sys.argv) != 3:
    sys.exit('usage: warp.py X Y')
x, y = int(sys.argv[1]), int(sys.argv[2])

Xlib = ctypes.CDLL(ctypes.util.find_library('X11'))
Xlib.XOpenDisplay.restype = ctypes.c_void_p
display = os.environ.get('DISPLAY')
d = Xlib.XOpenDisplay(display.encode() if display else None)
if not d:
    sys.exit('warp.py: cannot open display')
root = Xlib.XDefaultRootWindow(ctypes.c_void_p(d))
Xlib.XWarpPointer(ctypes.c_void_p(d), 0, root, 0, 0, 0, 0, x, y)
Xlib.XFlush(ctypes.c_void_p(d))
