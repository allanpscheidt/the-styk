import os
import re
import subprocess
import urllib.parse
from gi.repository import GLib, Gio

class RECT:
    def __init__(self, left: int, top: int, right: int, bottom: int):
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom

    @property
    def width(self) -> int:
        return self.right - self.left

    @property
    def height(self) -> int:
        return self.bottom - self.top

    def equals(self, other: "RECT") -> bool:
        return (self.left == other.left and 
                self.top == other.top and 
                self.right == other.right and 
                self.bottom == other.bottom)

    def __repr__(self):
        return f"RECT(L={self.left}, T={self.top}, R={self.right}, B={self.bottom})"

class FileExplorerObserver:
    def __init__(self):
        self.change_callbacks = []
        self._current_folder = None
        self._current_bounds = None
        
        self._nautilus_last_paths = {}  # Map window/tab object_path -> last folder path
        self._last_nautilus_path = None
        
        # Connect to Session DBus to monitor Nautilus navigation signals
        try:
            self._dbus_conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            if self._dbus_conn:
                # Subscribe to Nautilus window property changes
                self._dbus_conn.signal_subscribe(
                    None,  # sender
                    "org.freedesktop.DBus.Properties",
                    "PropertiesChanged",
                    None,  # object_path
                    None,  # arg0
                    Gio.DBusSignalFlags.NONE,
                    self._on_dbus_properties_changed,
                    None
                )
                print("[Observer] Connected to Session DBus to monitor folder changes.")
        except Exception as e:
            print(f"[Observer] Failed to connect to DBus: {e}")

    def register_change_callback(self, cb):
        if cb not in self.change_callbacks:
            self.change_callbacks.append(cb)

    @property
    def current_folder(self) -> str:
        return self._current_folder

    @property
    def current_bounds(self) -> RECT:
        return self._current_bounds

    def start(self):
        # Poll every 800ms, running on GTK main loop (main thread)
        GLib.timeout_add(800, self._poll)
        self._poll()  # Immediate first poll

    def _extract_uris(self, value) -> list:
        uris = []
        if isinstance(value, str):
            if value.startswith("file://"):
                uris.append(value)
        elif isinstance(value, list):
            for item in value:
                uris.extend(self._extract_uris(item))
        elif isinstance(value, dict):
            for v in value.values():
                uris.extend(self._extract_uris(v))
        return uris

    def _on_dbus_properties_changed(self, connection, sender, object_path, interface, signal, parameters, user_data):
        # Debug print to see what signals we are receiving
        try:
            unpacked = parameters.unpack()
            print(f"[Observer] D-Bus signal received! Path: {object_path}, Interface: {interface}, Params: {unpacked}")
        except Exception as e:
            print(f"[Observer] D-Bus unpack failed: {e}")
            return

        if "/org/gnome/Nautilus/window" not in object_path and "/org/freedesktop/FileManager1" not in object_path:
            return

        try:
            if len(unpacked) >= 2:
                changed_properties = unpacked[1]
                
                # Check if all folders were closed (OpenLocations becomes empty)
                if "OpenLocations" in changed_properties:
                    locations = changed_properties["OpenLocations"]
                    if isinstance(locations, list) and len(locations) == 0:
                        self._last_nautilus_path = None
                        self._nautilus_last_paths.clear()
                        print("[Observer] DBus detected all folders closed.")
                        return

                # Try to find a URI/path in the changed properties
                for key, val in changed_properties.items():
                    uris = self._extract_uris(val)
                    if uris:
                        # Use the last extracted URI as the most recently updated location
                        parsed_path = self._uri_to_path(uris[-1])
                        if parsed_path:
                            self._nautilus_last_paths[object_path] = parsed_path
                            self._last_nautilus_path = parsed_path
                            print(f"[Observer] DBus detected folder change: {parsed_path}")
        except Exception as e:
            print(f"[Observer] DBus parsing exception: {e}")
            pass

    def _uri_to_path(self, uri: str) -> str:
        try:
            # Remove file:// and decode URI characters (like %20)
            if uri.startswith("file://"):
                path = uri[7:]
                return urllib.parse.unquote(path)
        except Exception:
            pass
        return None

    def _get_active_window_info(self):
        """
        Queries X11 active window using xprop and xwininfo.
        Returns: (window_id, window_class, window_title, bounds_rect)
        """
        try:
            # Get active window ID
            out = subprocess.check_output(["xprop", "-root", "_NET_ACTIVE_WINDOW"], stderr=subprocess.DEVNULL)
            match = re.search(r"_NET_ACTIVE_WINDOW\(WINDOW\): window id # (0x[0-9a-fA-F]+)", out.decode("utf-8"))
            if not match:
                return None, None, None, None
            
            win_id = match.group(1)
            
            # Get window class
            class_out = subprocess.check_output(["xprop", "-id", win_id, "WM_CLASS"], stderr=subprocess.DEVNULL)
            class_match = re.search(r'WM_CLASS\(STRING\) = "([^"]+)", "([^"]+)"', class_out.decode("utf-8"))
            win_class = class_match.group(2) if class_match else ""
            
            # Get window title
            title_out = subprocess.check_output(["xprop", "-id", win_id, "_NET_WM_NAME"], stderr=subprocess.DEVNULL)
            title_match = re.search(r'_NET_WM_NAME\(UTF8_STRING\) = "([^"]+)"', title_out.decode("utf-8"))
            if not title_match:
                title_out = subprocess.check_output(["xprop", "-id", win_id, "WM_NAME"], stderr=subprocess.DEVNULL)
                title_match = re.search(r'WM_NAME\(STRING\) = "([^"]+)"', title_out.decode("utf-8"))
            
            win_title = title_match.group(1) if title_match else ""
            
            # Get window geometry/bounds
            wininfo = subprocess.check_output(["xwininfo", "-id", win_id], stderr=subprocess.DEVNULL).decode("utf-8")
            
            x_match = re.search(r"Absolute upper-left X:\s+(-?\d+)", wininfo)
            y_match = re.search(r"Absolute upper-left Y:\s+(-?\d+)", wininfo)
            w_match = re.search(r"Width:\s+(\d+)", wininfo)
            h_match = re.search(r"Height:\s+(\d+)", wininfo)
            
            if x_match and y_match and w_match and h_match:
                x = int(x_match.group(1))
                y = int(y_match.group(1))
                w = int(w_match.group(1))
                h = int(h_match.group(1))
                bounds = RECT(x, y, x + w, y + h)
            else:
                bounds = None
                
            return win_id, win_class, win_title, bounds
        except Exception:
            return None, None, None, None

    def _poll(self) -> bool:
        # Get active window info
        win_id, win_class, win_title, bounds = self._get_active_window_info()
        
        # If it's our own window, ignore and keep current state (so notes stay visible)
        if win_class in ("TheStyk", "the-styk", "main.py"):
            return True

        if not win_class:
            # We are likely on Wayland or tools like xprop are missing.
            # We fall back to the last navigated Nautilus path from DBus.
            if self._last_nautilus_path:
                folder_path = self._last_nautilus_path.replace("\\", "/")
                if folder_path.endswith("/") and len(folder_path) > 1:
                    folder_path = folder_path.rstrip("/")
                
                if folder_path != self._current_folder:
                    self._current_folder = folder_path
                    self._current_bounds = None
                    self._notify_change()
            else:
                self._clear_folder_state()
            return True

        # Check if the active window is a known file manager
        # Common classes: "Nautilus" (GNOME), "Dolphin" (KDE), "Nemo" (Cinnamon), "Thunar" (XFCE)
        file_managers = ["nautilus", "dolphin", "nemo", "thunar", "pcmanfm"]
        is_file_manager = any(fm in win_class.lower() for fm in file_managers)
        
        if not is_file_manager:
            self._clear_folder_state()
            return True

        folder_path = None
        
        # Method 1: Nautilus D-Bus cached path
        if "nautilus" in win_class.lower() and self._last_nautilus_path:
            folder_path = self._last_nautilus_path
        
        # Method 2: Fallback to title parsing if the file manager displays absolute paths in the window title
        # E.g. /home/user/Documents or ~/Documents
        if not folder_path and win_title:
            if win_title.startswith("/") or win_title.startswith("~"):
                # Clean up title if it contains suffixes
                clean_title = win_title.split(" — ")[0].strip()
                if clean_title.startswith("~"):
                    clean_title = os.path.expanduser(clean_title)
                if os.path.isdir(clean_title):
                    folder_path = clean_title

        # Method 3: Fallback to checking Nautilus path directly
        if not folder_path and "nautilus" in win_class.lower():
            # If no DBus signal was caught yet, try to read the active URI by querying Nautilus over DBus directly
            try:
                # We can call org.freedesktop.FileManager1 to check paths, but since we cannot poll all tabs easily,
                # we just use the last navigated path or fall back.
                pass
            except Exception:
                pass

        if not folder_path:
            self._clear_folder_state()
            return True

        # Normalized path
        folder_path = folder_path.replace("\\", "/")
        if folder_path.endswith("/") and len(folder_path) > 1:
            folder_path = folder_path.rstrip("/")

        # Check if anything changed
        if (folder_path != self._current_folder or 
            self._current_bounds is None or 
            (bounds and not bounds.equals(self._current_bounds))):
            
            self._current_folder = folder_path
            self._current_bounds = bounds
            self._notify_change()

        return True

    def _clear_folder_state(self):
        if self._current_folder is not None or self._current_bounds is not None:
            self._current_folder = None
            self._current_bounds = None
            self._notify_change()

    def _notify_change(self):
        for cb in self.change_callbacks:
            try:
                cb(self._current_folder, self._current_bounds)
            except Exception as e:
                print(f"[Observer] Error invoking callback: {e}")
