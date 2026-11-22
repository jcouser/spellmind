"""Spellmind's Linux capture helper (core/capture_x11.py, adapted from NeverQuestAlone's): its decoder finds
Spellmind's strip (magic 534D) at the window's corner and 272 px down (beside NeverQuestAlone's), remembers
which, reads a tall enough area, and looks for WoW Forever's Wow.exe. The helpers below are NeverQuestAlone's
(tests/byok/capture_x11_test.py, MIT; see NOTICE.md).

Run by tests/link/capture_x11_test.mjs (python3 tests/link/capture_x11_test.py). No display, no packages.
"""

import importlib.util
import math
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "..", "core", "capture_x11.py")
_spec = importlib.util.spec_from_file_location("capture_x11", SCRIPT)
cx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cx)

SM = (0x53, 0x4D)
NQA = (0xC7, 0x2C)


def frame_cells(frame_id, payload, magic):
    data = bytes([magic[0], magic[1], frame_id >> 8, frame_id & 255, len(payload) >> 8, len(payload) & 255]) + payload
    s1 = s2 = 0
    for b in data[2:]:
        s1 = (s1 + b) % 255
        s2 = (s2 + s1) % 255
    data += bytes([s1, s2])
    cells, acc, nbits = [], 0, 0
    for b in data:
        acc = (acc << 8) | b
        nbits += 8
        while nbits >= 3:
            cells.append((acc >> (nbits - 3)) & 7)
            nbits -= 3
            acc &= (1 << nbits) - 1
    if nbits:
        cells.append((acc << (3 - nbits)) & 7)
    return cells


def image(cells, pitch, x0=0, y0=0, width=1300, height=640, cells_per_row=200):
    """Point-sampled rendering: each pixel shows the cell under its center."""
    def px(x, y):
        c = int(math.floor((x + 0.5 - x0) / pitch))
        r = int(math.floor((y + 0.5 - y0) / pitch))
        if x < x0 or y < y0 or c >= cells_per_row or c < 0 or r < 0:
            return (0x30, 0x2A, 0x26)
        i = r * cells_per_row + c
        v = cells[i] if i < len(cells) else 0
        return (255 if v & 4 else 0, 255 if v & 2 else 0, 255 if v & 1 else 0)
    return px, width, height


def use(argv):
    cx.configure(cx.build_parser().parse_args(argv))


class Defaults(unittest.TestCase):
    def test_spellmind_magic_and_wow_forever(self):
        a = cx.build_parser().parse_args([])
        self.assertEqual(a.magic, SM)
        self.assertEqual(a.process_name, "Wow")
        self.assertEqual(cx.KNOWN_MAGICS["534D"], "Spellmind")


class Strip(unittest.TestCase):
    def setUp(self):
        use([])

    def test_at_the_corner(self):
        px, w, h = image(frame_cells(7, b"hello from Spellmind", SM), 4)
        msg, hint = cx.find_and_decode(px, w, h, None)
        self.assertEqual(msg, {"id": 7, "text": "hello from Spellmind"})
        self.assertEqual(hint[3], 0)

    def test_272_px_down_beside_neverquestalone(self):
        px, w, h = image(frame_cells(8, b"below the corner", SM), 4, y0=272)
        msg, hint = cx.find_and_decode(px, w, h, None)
        self.assertEqual(msg, {"id": 8, "text": "below the corner"})
        self.assertEqual(hint[3], 272)
        # The next frame, at the same place: found from the hint.
        px2, w2, h2 = image(frame_cells(9, b"again", SM), 4, y0=272)
        self.assertEqual(cx.find_and_decode(px2, w2, h2, hint)[0], {"id": 9, "text": "again"})

    def test_a_neverquestalone_strip_isnt_read_as_spellmind(self):
        px, w, h = image(frame_cells(5, b"not ours", NQA), 4)
        msg, _ = cx.find_and_decode(px, w, h, None)
        self.assertTrue(msg is None or msg.get("error"))

    def test_the_area_read_reaches_the_lower_strip(self):
        self.assertGreaterEqual(cx.GRAB_H, 272 + cx.MAXROWS * cx.CELL)

    def test_only_the_corner_when_told(self):
        use(["--strip-y", "0"])
        self.assertEqual(cx.STRIP_YS, (0,))
        px, w, h = image(frame_cells(8, b"below the corner", SM), 4, y0=272)
        msg, _ = cx.find_and_decode(px, w, h, None)
        self.assertTrue(msg is None or msg.get("error"))

    def test_scaled_strip_down_below_with_pitch_search(self):
        use(["--pitch-search"])
        text = b"scaled " * 30
        px, w, h = image(frame_cells(10, text, SM), 5, x0=2, y0=273)
        msg, hint = cx.find_and_decode(px, w, h, None)
        self.assertEqual(msg, {"id": 10, "text": text.decode()})
        self.assertEqual(hint[3], 272)


class Window(unittest.TestCase):
    """Which window is the game's (issue #1: under Proton through Faugus, the class isn't wow.exe)."""

    def test_wine_class(self):
        self.assertTrue(cx.matches(["wow.exe", "wow.exe"], "World of Warcraft"))
        self.assertTrue(cx.matches(["Wow.exe"], ""))

    def test_proton_class_by_title(self):
        self.assertTrue(cx.matches(["steam_app_default", "steam_app_default"], "World of Warcraft"))
        self.assertTrue(cx.matches(["steam_app_0"], " World of Warcraft "))

    def test_not_a_browser_tab_or_the_launcher(self):
        self.assertFalse(cx.matches(["firefox", "Navigator"], "Quests - World of Warcraft - Wowhead"))
        self.assertFalse(cx.matches(["battle.net.exe"], "Battle.net"))
        self.assertFalse(cx.matches(["steam_app_default"], ""))

    def test_by_name_when_told(self):
        self.assertTrue(cx.matches(["x"], "My WoW Window", window_name="wow window"))
        self.assertFalse(cx.matches(["wow.exe"], "Other", window_name="wow window"))

    def test_list_windows_flag(self):
        self.assertTrue(cx.build_parser().parse_args(["--list-windows"]).list_windows)


class NoWindow(unittest.TestCase):
    """Why the game isn't found: Wine's Wayland driver (a game process, no X11 window) is said in words."""

    def fake_proc(self, cmdlines):
        import tempfile
        d = tempfile.mkdtemp()
        for i, cmd in enumerate(cmdlines, start=100):
            os.makedirs(os.path.join(d, str(i)))
            with open(os.path.join(d, str(i), "cmdline"), "wb") as fh:
                fh.write(cmd.encode().replace(b" ", b"\0"))
        return d

    def test_wayland_driver(self):
        proc = self.fake_proc(["/usr/bin/python3 foo.py", "Z:\\home\\me\\Faugus\\wow\\drive_c\\World of Warcraft\\_forever_\\Wow.exe -launcher"])
        kind, text = cx.no_window_reason("Wow", proc, {"WAYLAND_DISPLAY": "wayland-0"})
        self.assertEqual(kind, "wayland_native")
        self.assertIn("PROTON_ENABLE_WAYLAND=0", text)

    def test_not_running(self):
        proc = self.fake_proc(["/usr/bin/firefox", "/usr/bin/wowup"])
        self.assertEqual(cx.no_window_reason("Wow", proc, {"WAYLAND_DISPLAY": "wayland-0"})[0], "window_not_found")

    def test_x11_session_is_just_waiting(self):
        proc = self.fake_proc(["C:\\Games\\Wow.exe"])
        self.assertEqual(cx.no_window_reason("Wow", proc, {})[0], "window_not_found")


if __name__ == "__main__":
    unittest.main()
