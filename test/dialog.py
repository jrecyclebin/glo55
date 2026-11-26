#!/usr/bin/env python3
"""A floating dialog for the tests (python3 + ctypes + libX11, nothing to install).

    dialog.py TITLE [WIDTH HEIGHT [X Y]]

The window carries WM_TRANSIENT_FOR, so the WM floats it (centred unless X Y is
given). It selects pointer motion for itself, as real toolkits do, so none of it
propagates to the WM's frame. Stays up until it is killed."""
import ctypes, ctypes.util, sys, time

X = ctypes.CDLL(ctypes.util.find_library("X11"))
X.XOpenDisplay.restype = ctypes.c_void_p
X.XDefaultRootWindow.restype = X.XCreateSimpleWindow.restype = ctypes.c_ulong
dpy = X.XOpenDisplay(None)
if not dpy:
    sys.exit("cannot open display")
dpy = ctypes.c_void_p(dpy)
root = ctypes.c_ulong(X.XDefaultRootWindow(dpy))
title = sys.argv[1]
w, h = map(int, sys.argv[2:4] or (300, 200))
x, y = map(int, sys.argv[4:6] or (0, 0))
win = ctypes.c_ulong(X.XCreateSimpleWindow(dpy, root, x, y, w, h, 0, ctypes.c_ulong(0), ctypes.c_ulong(0xFFFFFF)))
X.XStoreName(dpy, win, title.encode())
X.XSetTransientForHint(dpy, win, root)
X.XSelectInput(dpy, win, ctypes.c_long(0x40))  # PointerMotionMask
X.XMapWindow(dpy, win)
X.XFlush(dpy)
while True:
    time.sleep(1)
