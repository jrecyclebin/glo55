#!/usr/bin/env python3
"""Tiny X client for the Unicode tests (python3 + ctypes + libX11, nothing to install).

    titleclient.py MODE TITLE [NEW_TITLE]

MODE decides which title properties the window carries:
  utf8    _NET_WM_NAME (UTF8_STRING) and WM_NAME (UTF8_STRING)  - what modern toolkits do
  net     only _NET_WM_NAME
  latin1  only WM_NAME, type STRING, ISO-8859-1 bytes           - an old Xlib client
  ctext   only WM_NAME, type COMPOUND_TEXT                      - xterm and other legacy clients
  badutf8 _NET_WM_NAME holding invalid UTF-8 bytes
If NEW_TITLE is given it replaces the title after one second (PropertyNotify path).
The window is filled white and stays up until it is killed."""
import ctypes, ctypes.util, sys, time, locale

locale.setlocale(locale.LC_ALL, "")
X = ctypes.CDLL(ctypes.util.find_library("X11"))
X.XOpenDisplay.restype = ctypes.c_void_p
X.XInternAtom.restype = ctypes.c_ulong
X.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
X.XCreateSimpleWindow.restype = ctypes.c_ulong
X.XCreateSimpleWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong] + [ctypes.c_int] * 4 + [ctypes.c_uint] + [ctypes.c_ulong] * 2
X.XDefaultRootWindow.restype = ctypes.c_ulong
X.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
X.XChangeProperty.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_int,
                              ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
X.XMapWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
X.XFlush.argtypes = [ctypes.c_void_p]


class TextProperty(ctypes.Structure):
    _fields_ = [("value", ctypes.c_void_p), ("encoding", ctypes.c_ulong), ("format", ctypes.c_int), ("nitems", ctypes.c_ulong)]


dpy = X.XOpenDisplay(None)
if not dpy:
    sys.exit("cannot open display")
atom = lambda n: X.XInternAtom(dpy, n.encode(), 0)
win = X.XCreateSimpleWindow(dpy, X.XDefaultRootWindow(dpy), 0, 0, 300, 200, 0, 0, 0xffffff)


def set_prop(name, typ, data):
    X.XChangeProperty(dpy, win, atom(name), atom(typ), 8, 0, data, len(data))


def set_title(mode, title):
    if mode in ("utf8", "net"):
        set_prop("_NET_WM_NAME", "UTF8_STRING", title.encode())
    if mode == "utf8":
        set_prop("WM_NAME", "UTF8_STRING", title.encode())
    if mode == "latin1":
        set_prop("WM_NAME", "STRING", title.encode("latin-1", "replace"))
    if mode == "badutf8":
        set_prop("_NET_WM_NAME", "UTF8_STRING", title.encode() + b" \xe9\xff\xc3")
    if mode == "ctext":
        tp = TextProperty()
        arr = (ctypes.c_char_p * 1)(title.encode())
        # XCompoundTextStyle = 1, via the Xutf8 converter
        X.Xutf8TextListToTextProperty(ctypes.c_void_p(dpy), arr, 1, 1, ctypes.byref(tp))
        X.XChangeProperty(ctypes.c_void_p(dpy), win, atom("WM_NAME"), tp.encoding, tp.format, 0,
                          ctypes.c_char_p(tp.value), int(tp.nitems))
    X.XFlush(dpy)


mode, title = sys.argv[1], sys.argv[2]
set_title(mode, title)
X.XMapWindow(dpy, win)
X.XFlush(dpy)
if len(sys.argv) > 3:
    time.sleep(1.0)
    set_title(mode, sys.argv[3])
while True:
    time.sleep(1)
