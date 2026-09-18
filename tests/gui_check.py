"""Native Windows smoke check: real mouse/key input into the Godot window."""
import ctypes
from ctypes import wintypes
import pathlib
import subprocess
import time
from PIL import ImageGrab

ROOT = pathlib.Path(__file__).resolve().parents[1]
user32 = ctypes.windll.user32
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except OSError:
    user32.SetProcessDPIAware()
log = (ROOT / 'tests' / 'gui_run.log').open('w', encoding='utf-8')
process = subprocess.Popen([
    str(ROOT / 'tools' / 'godot' / 'Godot_v4.5.1-stable_win64.exe'),
    '--path', str(ROOT), '--resolution', '1280x720', '--position', '40,40', '--max-fps', '60'
], stdout=log, stderr=subprocess.STDOUT)
time.sleep(7)
windows = []
CALLBACK = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
@CALLBACK
def callback(hwnd, _):
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    if pid.value == process.pid and user32.IsWindowVisible(hwnd):
        windows.append(hwnd)
    return True
user32.EnumWindows(callback, 0)
if not windows:
    raise RuntimeError('Godot game window not found')
hwnd = windows[0]
user32.ShowWindow(hwnd, 9)
user32.SetWindowPos(hwnd, -1, 40, 40, 1296, 759, 0x0040)
user32.keybd_event(0x12, 0, 0, 0)
user32.SetForegroundWindow(hwnd)
user32.keybd_event(0x12, 0, 2, 0)
time.sleep(0.5)
point = wintypes.POINT(0, 0)
user32.ClientToScreen(hwnd, ctypes.byref(point))
rect = wintypes.RECT()
user32.GetClientRect(hwnd, ctypes.byref(rect))
scale_x, scale_y = rect.right / 1280, rect.bottom / 720
print('Window', hwnd, 'client', rect.right, rect.bottom, 'origin', point.x, point.y, 'foreground', user32.GetForegroundWindow())

def key(vk, seconds=0.1):
    scan = user32.MapVirtualKeyW(vk, 0)
    user32.keybd_event(vk, scan, 0, 0)
    time.sleep(seconds)
    user32.keybd_event(vk, scan, 2, 0)

def screenshot(name):
    rect = wintypes.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(rect))
    ImageGrab.grab(bbox=(point.x, point.y, point.x + rect.right, point.y + rect.bottom)).save(ROOT / 'tests' / name)

user32.SetCursorPos(point.x + int(200 * scale_x), point.y + int(382 * scale_y))
time.sleep(0.3)
user32.mouse_event(2, 0, 0, 0, 0)
time.sleep(0.15)
user32.mouse_event(4, 0, 0, 0, 0)
time.sleep(1)
key(0x57, 0.7)
screenshot('09_gui_play.png')
key(0x54)
time.sleep(1)
user32.mouse_event(2, 0, 0, 0, 0)
time.sleep(0.45)
user32.mouse_event(4, 0, 0, 0, 0)
time.sleep(0.3)
screenshot('10_gui_fire.png')
key(0x52)
time.sleep(2)
key(0x47)
time.sleep(0.8)
screenshot('17_gui_course.png')
key(0x1B)
time.sleep(0.5)
screenshot('11_gui_pause.png')
print(f'Native GUI interactions completed, game PID {process.pid}, left paused.')
