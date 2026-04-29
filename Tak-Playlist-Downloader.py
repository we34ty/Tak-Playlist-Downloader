#!/usr/bin/env python3
"""
YouTube Playlist Downloader GUI
Cross-platform GUI for Download-Playlist, Retry-Failed, and Move-Recovered scripts
"""

import os
import sys
import subprocess
import threading
import platform
import json
import re
import tkinter as tk
from tkinter import ttk, filedialog, messagebox, scrolledtext
from pathlib import Path
from datetime import datetime, time, timedelta
import time as time_module
import uuid
from queue import Queue
import atexit
import getpass

# Try to import pystray for system tray support
PYSTRAY_AVAILABLE = False
try:
    import pystray
    from PIL import Image, ImageDraw
    PYSTRAY_AVAILABLE = True
except ImportError:
    print("Note: pystray not installed. System tray not available.")
    print("Install with: pip install pystray pillow")

# Function to strip ANSI color codes
def strip_ansi_codes(text):
    """Remove ANSI escape sequences (color codes) from text"""
    ansi_escape = re.compile(r'\x1B\[[0-?]*[ -/]*[@-~]')
    return ansi_escape.sub('', text)


class ScheduledTask:
    """Class representing a scheduled download task"""
    def __init__(self, task_id, name, playlist_url, output_dir, schedule_type, interval,
                 enable_time_window, start_hour, start_minute, end_hour, end_minute,
                 enable_specific_time, specific_hour, specific_minute,
                 format_type, quality, enable_archive, enabled=True):
        self.id = task_id
        self.name = name
        self.playlist_url = playlist_url
        self.output_dir = output_dir
        self.schedule_type = schedule_type
        self.interval = interval
        self.enable_time_window = enable_time_window
        self.start_hour = start_hour
        self.start_minute = start_minute
        self.end_hour = end_hour
        self.end_minute = end_minute
        self.enable_specific_time = enable_specific_time
        self.specific_hour = specific_hour
        self.specific_minute = specific_minute
        self.format = format_type
        self.quality = quality
        self.enable_archive = enable_archive
        self.enabled = enabled
        self.running = False
        self.last_run = None
        self.next_run = None
        self.process = None
        
        # New fields for tracking interval progress
        self.last_completion_time = None  # When the last download finished
        self.last_start_time = None       # When the last download started
        self.remaining_downloads = None   # For playlist resume (number of videos left)
        self.interrupted = False           # Whether the last run was interrupted
    
    def to_dict(self):
        """Convert to dictionary for JSON serialization"""
        return {
            "id": self.id,
            "name": self.name,
            "playlist_url": self.playlist_url,
            "output_dir": self.output_dir,
            "schedule_type": self.schedule_type,
            "interval": self.interval,
            "enable_time_window": self.enable_time_window,
            "start_hour": self.start_hour,
            "start_minute": self.start_minute,
            "end_hour": self.end_hour,
            "end_minute": self.end_minute,
            "enable_specific_time": self.enable_specific_time,
            "specific_hour": self.specific_hour,
            "specific_minute": self.specific_minute,
            "format": self.format,
            "quality": self.quality,
            "enable_archive": self.enable_archive,
            "enabled": self.enabled,
            "last_completion_time": self.last_completion_time,
            "last_start_time": self.last_start_time,
            "remaining_downloads": self.remaining_downloads,
            "interrupted": self.interrupted
        }
    
    @classmethod
    def from_dict(cls, data):
        """Create from dictionary"""
        task = cls(
            task_id=data["id"],
            name=data["name"],
            playlist_url=data["playlist_url"],
            output_dir=data["output_dir"],
            schedule_type=data["schedule_type"],
            interval=data["interval"],
            enable_time_window=data["enable_time_window"],
            start_hour=data["start_hour"],
            start_minute=data["start_minute"],
            end_hour=data["end_hour"],
            end_minute=data["end_minute"],
            enable_specific_time=data["enable_specific_time"],
            specific_hour=data["specific_hour"],
            specific_minute=data["specific_minute"],
            format_type=data["format"],
            quality=data["quality"],
            enable_archive=data["enable_archive"],
            enabled=data["enabled"]
        )
        # Restore tracking fields
        task.last_completion_time = data.get("last_completion_time")
        task.last_start_time = data.get("last_start_time")
        task.remaining_downloads = data.get("remaining_downloads")
        task.interrupted = data.get("interrupted", False)
        return task
    
    def get_next_interval_run_time(self):
        """Calculate when the next run should occur based on interval and last completion"""
        # Get the appropriate reference time (prefer completion time over start time)
        reference_time = self.last_completion_time
        if reference_time is None:
            reference_time = self.last_run
        
        if reference_time is None:
            # Never ran before, run now
            return datetime.now()
        
        try:
            last_run_time = datetime.fromisoformat(reference_time)
            
            if self.schedule_type == "minutes":
                next_run = last_run_time + timedelta(minutes=self.interval)
            elif self.schedule_type == "hours":
                next_run = last_run_time + timedelta(hours=self.interval)
            elif self.schedule_type == "days":
                next_run = last_run_time + timedelta(days=self.interval)
            elif self.schedule_type == "weeks":
                next_run = last_run_time + timedelta(weeks=self.interval)
            elif self.schedule_type == "months":
                next_run = last_run_time + timedelta(days=self.interval * 30)
            else:
                return datetime.now()
            
            # If next run is more than 5 seconds in the past, run now
            if next_run <= datetime.now():
                return datetime.now()
            
            return next_run
        except:
            return datetime.now()


class YouTubeDownloaderGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Tak Playlist Downloader")
        self.root.geometry("1100x800")
        self.root.minsize(900, 700)
        self.root.resizable(True, True)
        
        # Check for --minimized argument
        start_minimized = '--minimized' in sys.argv
        
        # System tray variables
        self.tray_icon = None
        self.minimized_to_tray = False
        self.tray_thread = None

        # Scheduler variables
        self.scheduler_running = False
        self.scheduler_thread = None
        self.tasks = {}
        self.task_queue = Queue()
        self.current_process = None
        
        # Dark mode variable
        self.dark_mode = tk.BooleanVar(value=False)
        
        # Detect OS and set script extension
        self.os_type = platform.system()
        if self.os_type == "Windows":
            self.script_ext = ".ps1"
            self.tray_enabled = True
        else:
            self.script_ext = ".sh"
            self.tray_enabled = False
            print("System tray disabled on Linux for better compatibility")
        
        windows_theme = self.get_windows_theme()
        if windows_theme is not None:
            self.dark_mode.set(windows_theme)
        
        # Override PYSTRAY_AVAILABLE based on OS
        global PYSTRAY_AVAILABLE
        if not self.tray_enabled:
            PYSTRAY_AVAILABLE = False
        
        # Get the correct directory for saving settings
        self.config_dir = self.get_config_dir()
        
        # Settings file path
        self.settings_file = self.config_dir / "tak_downloader_settings.json"
        self.tasks_file = self.config_dir / "tak_downloader_tasks.json"
        
        # Script directory
        if getattr(sys, 'frozen', False):
            self.script_dir = Path(os.path.dirname(sys.executable))
        else:
            self.script_dir = Path(__file__).parent
        
        self.current_browse_dir = str(Path.cwd())
        self.tak_data_dir = ".TakData"
        
        # Set up the UI
        self.setup_ui()
        
        # Apply dark mode if saved
        self.load_settings()
        if self.dark_mode.get():
            self.toggle_dark_mode()
        
        self.load_tasks()
        
        # Bind window events - THIS IS THE CRITICAL FIX
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)
        
        # Set up system tray (Windows only)
        if PYSTRAY_AVAILABLE and self.tray_enabled:
            self.root.after(100, self.setup_tray)
        
        # Start background task processor
        self.start_task_processor()
        
        # Start scheduler if there are enabled tasks
        self.check_and_start_scheduler()
        
        # Register cleanup on exit
        atexit.register(self.cleanup)
        
        # If start_minimized, minimize to tray
        if start_minimized and self.tray_enabled:
            self.root.after(100, self.minimize_to_tray)
    
    def get_config_dir(self):
        """Get the user's config directory for storing settings"""
        if self.os_type == "Windows":
            base_dir = Path(os.environ.get('APPDATA', Path.home() / 'AppData/Roaming'))
        else:
            base_dir = Path.home() / '.config'
        
        config_dir = base_dir / 'TakDownloader'
        config_dir.mkdir(parents=True, exist_ok=True)
        return config_dir
    
    def get_autostart_path(self):
        """Get the path to the autostart file/folder based on OS"""
        if self.os_type == "Windows":
            return Path(os.environ.get('APPDATA', Path.home() / 'AppData/Roaming')) / 'Microsoft' / 'Windows' / 'Start Menu' / 'Programs' / 'Startup'
        else:
            return Path.home() / '.config' / 'autostart'
    
    def get_executable_path(self):
        """Get the path to the current executable/script"""
        if getattr(sys, 'frozen', False):
            return Path(sys.executable)
        else:
            return Path(sys.argv[0]).absolute()
    
    def is_autostart_enabled(self):
        """Check if autostart is currently enabled"""
        if self.os_type == "Windows":
            startup_folder = self.get_autostart_path()
            shortcut_path = startup_folder / "TakPlaylistDownloader.lnk"
            bat_path = startup_folder / "TakPlaylistDownloader.bat"
            return shortcut_path.exists() or bat_path.exists()
        else:
            autostart_file = self.get_autostart_path() / "tak-playlist-downloader.desktop"
            return autostart_file.exists()
    
    def create_windows_autostart(self):
        """Create Windows shortcut for autostart"""
        try:
            startup_folder = self.get_autostart_path()
            startup_folder.mkdir(parents=True, exist_ok=True)
            
            exe_path = self.get_executable_path()
            
            # Create a batch file
            bat_path = startup_folder / "TakPlaylistDownloader.bat"
            with open(bat_path, 'w') as f:
                f.write(f'@echo off\ncd /d "{exe_path.parent}"\n"{exe_path}" --minimized\n')
            return True
        except Exception as e:
            print(f"Failed to create Windows autostart: {e}")
            return False
    
    def create_linux_autostart(self):
        """Create Linux desktop file for autostart"""
        try:
            autostart_dir = self.get_autostart_path()
            autostart_dir.mkdir(parents=True, exist_ok=True)
            
            desktop_file = autostart_dir / "tak-playlist-downloader.desktop"
            exe_path = self.get_executable_path()
            
            if getattr(sys, 'frozen', False):
                command = f'"{exe_path}" --minimized'
            else:
                command = f'python3 "{exe_path}" --minimized'
            
            desktop_content = f"""[Desktop Entry]
Type=Application
Name=Tak Playlist Downloader
Comment=Download YouTube playlists
Exec={command}
Icon=applications-multimedia
Terminal=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
Categories=AudioVideo;Network;
"""
            with open(desktop_file, 'w') as f:
                f.write(desktop_content)
            
            os.chmod(desktop_file, 0o755)
            return True
        except Exception as e:
            print(f"Failed to create Linux autostart: {e}")
            return False
    
    def remove_windows_autostart(self):
        """Remove Windows autostart shortcut"""
        try:
            startup_folder = self.get_autostart_path()
            shortcut_path = startup_folder / "TakPlaylistDownloader.lnk"
            bat_path = startup_folder / "TakPlaylistDownloader.bat"
            
            if shortcut_path.exists():
                shortcut_path.unlink()
            if bat_path.exists():
                bat_path.unlink()
            return True
        except Exception as e:
            print(f"Failed to remove Windows autostart: {e}")
            return False
    
    def remove_linux_autostart(self):
        """Remove Linux autostart desktop file"""
        try:
            autostart_file = self.get_autostart_path() / "tak-playlist-downloader.desktop"
            if autostart_file.exists():
                autostart_file.unlink()
            return True
        except Exception as e:
            print(f"Failed to remove Linux autostart: {e}")
            return False
    
    def toggle_autostart(self):
        """Enable or disable autostart based on checkbox"""
        if self.autostart_var.get():
            if self.os_type == "Windows":
                success = self.create_windows_autostart()
            else:
                success = self.create_linux_autostart()
            
            if success:
                messagebox.showinfo("Autostart Enabled", 
                    "Tak Playlist Downloader will start automatically when your computer starts.\n\nThe app will start minimized to the system tray.")
            else:
                messagebox.showerror("Error", "Failed to enable autostart. Please check permissions.")
                self.autostart_var.set(False)
        else:
            if self.os_type == "Windows":
                success = self.remove_windows_autostart()
            else:
                success = self.remove_linux_autostart()
            
            if success:
                messagebox.showinfo("Autostart Disabled", "Autostart has been disabled.")
            else:
                messagebox.showerror("Error", "Failed to disable autostart.")
    
    def setup_styles(self):
        """Setup styles for the application based on dark mode setting"""
        if self.dark_mode.get():
            # Dark mode colors
            bg = "#2d2d2d"
            fg = "#ffffff"
            select_bg = "#0d7377"
            select_fg = "#ffffff"
            entry_bg = "#3c3c3c"
            button_bg = "#4a4a4a"
            trough_bg = "#1e1e1e"
        else:
            # Light mode colors
            bg = "#f0f0f0"
            fg = "#000000"
            select_bg = "#0078d4"
            select_fg = "#ffffff"
            entry_bg = "#ffffff"
            button_bg = "#e0e0e0"
            trough_bg = "#d0d0d0"
        
        # Configure root window background
        self.root.configure(bg=bg)
        
        # ========== CONFIGURE TTK STYLES ==========
        style = ttk.Style()
        
        # Force usage of 'clam' theme which supports custom colors better
        # On Windows, 'clam' theme works better than 'vista' or 'xpnative'
        try:
            style.theme_use('clam')
        except:
            pass  # Fall back to default theme
        
        # Configure base styles
        style.configure(".", background=bg, foreground=fg)
        style.configure("TFrame", background=bg)
        style.configure("TLabel", background=bg, foreground=fg)
        style.configure("TLabelframe", background=bg, foreground=fg)
        style.configure("TLabelframe.Label", background=bg, foreground=fg)
        
        # Button styles
        style.configure("TButton", background=button_bg, foreground=fg, borderwidth=1, padding=6)
        style.map("TButton",
            background=[("active", select_bg), ("pressed", select_bg)],
            foreground=[("active", select_fg), ("pressed", select_fg)])
        
        # Entry styles
        style.configure("TEntry", fieldbackground=entry_bg, foreground=fg, padding=4)
        style.map("TEntry",
            fieldbackground=[("focus", entry_bg)],
            foreground=[("focus", fg)],
            bordercolor=[("focus", select_bg)])
        
        # Combobox styles
        style.configure("TCombobox", fieldbackground=entry_bg, foreground=fg, padding=4)
        style.map("TCombobox",
            fieldbackground=[("readonly", entry_bg)],
            foreground=[("readonly", fg)],
            selectbackground=[("readonly", select_bg)],
            selectforeground=[("readonly", select_fg)])
        
        # Notebook (tabs) styles
        style.configure("TNotebook", background=bg, borderwidth=0)
        style.configure("TNotebook.Tab", background=button_bg, foreground=fg, padding=[12, 6])
        style.map("TNotebook.Tab",
            background=[("selected", select_bg), ("active", select_bg)],
            foreground=[("selected", select_fg), ("active", fg)])
        
        # Checkbutton styles
        style.configure("TCheckbutton", background=bg, foreground=fg)
        style.map("TCheckbutton",
            background=[("active", bg)],
            indicatorcolor=[("selected", select_bg)])
        
        # Progressbar styles
        style.configure("TProgressbar", background=select_bg, troughcolor=trough_bg)
        
        # Scrollbar styles
        style.configure("Vertical.TScrollbar", background=button_bg, troughcolor=trough_bg, arrowcolor=fg)
        style.configure("Horizontal.TScrollbar", background=button_bg, troughcolor=trough_bg, arrowcolor=fg)
        
        # ========== CONFIGURE TK WIDGETS ==========
        
        # Listbox (task list)
        if hasattr(self, 'task_listbox') and self.task_listbox:
            self.task_listbox.configure(
                bg=entry_bg,
                fg=fg,
                selectbackground=select_bg,
                selectforeground=select_fg,
                activestyle="none",
                relief="flat",
                bd=0,
                highlightthickness=0
            )
        
        # Text widgets (ScrolledText)
        text_widgets = ['download_status', 'retry_status', 'move_status', 'details_text', 'task_logs']
        for widget_name in text_widgets:
            if hasattr(self, widget_name) and getattr(self, widget_name):
                widget = getattr(self, widget_name)
                widget.configure(
                    bg=entry_bg,
                    fg=fg,
                    insertbackground=fg,  # Cursor color
                    selectbackground=select_bg,
                    selectforeground=select_fg,
                    relief="flat",
                    bd=0,
                    highlightthickness=0
                )
        
        # Progress bars (tkinter ttk already handled)
        
        # ========== CONFIGURE NOTEBOOK TABS BACKGROUND ==========
        # This is the key fix - manually set the background of each tab frame
        for tab_name in ['download_tab', 'retry_tab', 'move_tab', 'scheduler_tab', 'settings_tab']:
            if hasattr(self, tab_name) and getattr(self, tab_name):
                tab = getattr(self, tab_name)
                tab.configure(style="TFrame")
                # Also configure all children of the tab
                self._recursive_configure(tab, bg, fg, entry_bg, select_bg, select_fg)
        
        # Force update
        self.root.update_idletasks()

    def _recursive_configure(self, widget, bg, fg, entry_bg, select_bg, select_fg):
        """Recursively configure all child widgets"""
        try:
            # Configure based on widget type
            if isinstance(widget, ttk.Frame):
                widget.configure(style="TFrame")
            elif isinstance(widget, ttk.LabelFrame):
                widget.configure(style="TLabelframe")
            elif isinstance(widget, ttk.Label):
                widget.configure(style="TLabel")
            elif isinstance(widget, ttk.Button):
                widget.configure(style="TButton")
            elif isinstance(widget, ttk.Entry):
                widget.configure(style="TEntry")
            elif isinstance(widget, ttk.Combobox):
                widget.configure(style="TCombobox")
            elif isinstance(widget, ttk.Checkbutton):
                widget.configure(style="TCheckbutton")
            elif isinstance(widget, tk.Frame):
                widget.configure(bg=bg)
            elif isinstance(widget, tk.Label):
                widget.configure(bg=bg, fg=fg)
            elif isinstance(widget, tk.Listbox):
                widget.configure(bg=entry_bg, fg=fg, selectbackground=select_bg, selectforeground=select_fg)
            elif isinstance(widget, tk.Text):
                widget.configure(bg=entry_bg, fg=fg, insertbackground=fg, selectbackground=select_bg, selectforeground=select_fg)
        except:
            pass
        
        # Recursively configure children
        for child in widget.winfo_children():
            self._recursive_configure(child, bg, fg, entry_bg, select_bg, select_fg)

    def toggle_dark_mode(self):
        """Toggle dark mode for the application"""
        self.setup_styles()
        
        # Force refresh of the task list
        if hasattr(self, 'task_listbox') and self.task_listbox:
            current_selection = self.task_listbox.curselection()
            items = self.task_listbox.get(0, tk.END)
            self.task_listbox.delete(0, tk.END)
            for item in items:
                self.task_listbox.insert(tk.END, item)
            if current_selection:
                self.task_listbox.selection_set(current_selection[0])
        
        # Refresh notebook
        if hasattr(self, 'notebook'):
            self.notebook.configure(style="TNotebook")
        
        self.save_settings()

    def get_windows_theme(self):
        """Detect Windows dark mode setting (Windows 10/11)"""
        if self.os_type != "Windows":
            return None
        
        try:
            import winreg
            key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, 
                r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")
            value, _ = winreg.QueryValueEx(key, "AppsUseLightTheme")
            winreg.CloseKey(key)
            return value == 0  # 0 = dark mode, 1 = light mode
        except:
            return None
    
    def apply_dark_mode_to_widget(self, widget, bg, fg, select_bg, entry_bg, button_bg):
        """Recursively apply dark mode colors to widgets"""
        try:
            if isinstance(widget, ttk.Frame):
                widget.configure(style="TFrame")
            elif isinstance(widget, ttk.Label):
                widget.configure(style="TLabel")
            elif isinstance(widget, ttk.LabelFrame):
                widget.configure(style="TLabelframe")
            elif isinstance(widget, ttk.Button):
                widget.configure(style="TButton")
            elif isinstance(widget, ttk.Entry):
                widget.configure(style="TEntry")
            elif isinstance(widget, ttk.Combobox):
                widget.configure(style="TCombobox")
            elif isinstance(widget, ttk.Checkbutton):
                widget.configure(style="TCheckbutton")
            elif isinstance(widget, ttk.Notebook):
                widget.configure(style="TNotebook")
            elif isinstance(widget, tk.Text):
                widget.configure(bg=entry_bg, fg=fg, insertbackground=fg)
            elif isinstance(widget, tk.Listbox):
                widget.configure(bg=entry_bg, fg=fg, selectbackground=select_bg)
            elif isinstance(widget, tk.Frame):
                widget.configure(bg=bg)
        except Exception as e:
            pass  # Ignore widgets that don't support these options
        
        # Recursively apply to children
        for child in widget.winfo_children():
            self.apply_dark_mode_to_widget(child, bg, fg, select_bg, entry_bg, button_bg)
    
    def setup_ui(self):
        """Setup the entire user interface"""
        style = ttk.Style()
        try:
            # 'clam' theme works best for custom colors on Windows
            style.theme_use('clam')
        except:
            pass
        
        main_frame = ttk.Frame(self.root, padding="5")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        self.notebook = ttk.Notebook(main_frame)
        self.notebook.pack(fill=tk.BOTH, expand=True)
        
        # Create tabs
        self.download_tab = ttk.Frame(self.notebook)
        self.retry_tab = ttk.Frame(self.notebook)
        self.move_tab = ttk.Frame(self.notebook)
        self.scheduler_tab = ttk.Frame(self.notebook)
        self.settings_tab = ttk.Frame(self.notebook)
        
        self.notebook.add(self.download_tab, text="Download Playlist")
        self.notebook.add(self.retry_tab, text="Retry Failed")
        self.notebook.add(self.move_tab, text="Move Recovered")
        self.notebook.add(self.scheduler_tab, text="Scheduler")
        self.notebook.add(self.settings_tab, text="Settings")
        
        self.setup_download_tab()
        self.setup_retry_tab()
        self.setup_move_tab()
        self.setup_scheduler_tab()
        self.setup_settings_tab()
    
    def setup_download_tab(self):
        """Setup the Download Playlist tab"""
        main_frame = ttk.Frame(self.download_tab, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)
        main_frame.columnconfigure(1, weight=1)
        
        # Playlist URL
        ttk.Label(main_frame, text="Playlist URL:").grid(row=0, column=0, sticky=tk.W, pady=3)
        self.download_url = ttk.Entry(main_frame, width=80)
        self.download_url.grid(row=0, column=1, columnspan=3, sticky=tk.W+tk.E, pady=3)
        self.download_url.bind('<KeyRelease>', lambda e: self.save_settings())
        
        # Output Directory
        ttk.Label(main_frame, text="Output Directory:").grid(row=1, column=0, sticky=tk.W, pady=3)
        self.download_output = ttk.Entry(main_frame, width=70)
        self.download_output.grid(row=1, column=1, sticky=tk.W+tk.E, pady=3)
        self.download_output.bind('<KeyRelease>', lambda e: self.save_settings())
        ttk.Button(main_frame, text="Browse", command=lambda: self.browse_folder(self.download_output)).grid(row=1, column=2, padx=3)
        ttk.Button(main_frame, text="Use Current", command=lambda: self.set_current_path(self.download_output)).grid(row=1, column=3, padx=3)
        
        ttk.Label(main_frame, text="Note: All logs and settings are stored in '.TakData' subfolder", foreground="gray").grid(row=2, column=0, columnspan=4, sticky=tk.W, pady=2)
        
        ttk.Separator(main_frame, orient='horizontal').grid(row=3, column=0, columnspan=4, sticky=tk.W+tk.E, pady=5)
        
        # Options frame
        options_frame = ttk.LabelFrame(main_frame, text="Options", padding="8")
        options_frame.grid(row=4, column=0, columnspan=4, sticky=tk.W+tk.E, pady=5)
        options_frame.columnconfigure(1, weight=0)
        options_frame.columnconfigure(3, weight=1)
        
        ttk.Label(options_frame, text="Sleep Interval (seconds):").grid(row=0, column=0, sticky=tk.W, pady=3)
        self.download_sleep = ttk.Entry(options_frame, width=10)
        self.download_sleep.grid(row=0, column=1, sticky=tk.W, pady=3)
        self.download_sleep.bind('<KeyRelease>', lambda e: self.save_settings())
        ttk.Label(options_frame, text="(0 = no delay, default: 11)").grid(row=0, column=2, sticky=tk.W, padx=5)
        
        ttk.Label(options_frame, text="Format:").grid(row=1, column=0, sticky=tk.W, pady=3)
        self.download_format = ttk.Combobox(options_frame, values=["mp3", "m4a", "opus", "flac", "wav", "mp4", "webm", "mkv"], width=10)
        self.download_format.grid(row=1, column=1, sticky=tk.W, pady=3)
        self.download_format.bind('<<ComboboxSelected>>', lambda e: self.save_settings())
        
        ttk.Label(options_frame, text="Quality:").grid(row=1, column=2, sticky=tk.W, pady=3, padx=10)
        self.download_quality = ttk.Combobox(options_frame, values=["low", "mid", "high"], width=8)
        self.download_quality.grid(row=1, column=3, sticky=tk.W, pady=3)
        self.download_quality.bind('<<ComboboxSelected>>', lambda e: self.save_settings())
        
        self.download_archive = tk.BooleanVar()
        ttk.Checkbutton(options_frame, text="Enable Archive Recovery (-a)", variable=self.download_archive, command=self.save_settings).grid(row=2, column=0, columnspan=2, sticky=tk.W, pady=3)
        
        ttk.Button(options_frame, text="Load Settings from Folder", command=lambda: self.load_config_from_folder(self.download_output.get())).grid(row=2, column=2, columnspan=2, sticky=tk.E, pady=3)
        
        # Add to Scheduler button
        ttk.Button(options_frame, text="Add Current Settings to Scheduler", command=self.add_current_to_scheduler).grid(row=3, column=0, columnspan=4, sticky=tk.W, pady=5)
        
        # Progress frame
        progress_frame = ttk.LabelFrame(main_frame, text="Progress", padding="8")
        progress_frame.grid(row=5, column=0, columnspan=4, sticky=tk.W+tk.E+tk.N+tk.S, pady=5)
        progress_frame.columnconfigure(0, weight=1)
        progress_frame.rowconfigure(1, weight=1)
        
        self.download_progress = ttk.Progressbar(progress_frame, mode='indeterminate')
        self.download_progress.grid(row=0, column=0, sticky=tk.W+tk.E, pady=3)
        
        self.download_status = scrolledtext.ScrolledText(progress_frame, height=10, width=80)
        self.download_status.grid(row=1, column=0, sticky=tk.W+tk.E+tk.N+tk.S, pady=3)
        
        main_frame.rowconfigure(5, weight=1)
        
        button_frame = ttk.Frame(main_frame)
        button_frame.grid(row=6, column=0, columnspan=4, pady=8)
        
        self.download_btn = ttk.Button(button_frame, text="Start Download", command=lambda: self.run_script("download"))
        self.download_btn.pack(side=tk.LEFT, padx=5)
        
        ttk.Button(button_frame, text="Stop", command=self.stop_current_download).pack(side=tk.LEFT, padx=5)
        ttk.Button(button_frame, text="Clear Output", command=lambda: self.download_status.delete(1.0, tk.END)).pack(side=tk.LEFT, padx=5)
    
    def setup_retry_tab(self):
        """Setup the Retry Failed tab"""
        main_frame = ttk.Frame(self.retry_tab, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)
        main_frame.columnconfigure(1, weight=1)
        
        ttk.Label(main_frame, text="Working Directory:").grid(row=0, column=0, sticky=tk.W, pady=3)
        self.retry_output = ttk.Entry(main_frame, width=70)
        self.retry_output.grid(row=0, column=1, sticky=tk.W+tk.E, pady=3)
        self.retry_output.bind('<KeyRelease>', lambda e: self.save_settings())
        ttk.Button(main_frame, text="Browse", command=lambda: self.browse_folder(self.retry_output)).grid(row=0, column=2, padx=3)
        ttk.Button(main_frame, text="Use Current", command=lambda: self.set_current_path(self.retry_output)).grid(row=0, column=3, padx=3)
        
        ttk.Label(main_frame, text="Note: All logs and settings are stored in '.TakData' subfolder", foreground="gray").grid(row=1, column=0, columnspan=4, sticky=tk.W, pady=2)
        
        ttk.Separator(main_frame, orient='horizontal').grid(row=2, column=0, columnspan=4, sticky=tk.W+tk.E, pady=5)
        
        options_frame = ttk.LabelFrame(main_frame, text="Options", padding="8")
        options_frame.grid(row=3, column=0, columnspan=4, sticky=tk.W+tk.E, pady=5)
        options_frame.columnconfigure(1, weight=0)
        options_frame.columnconfigure(3, weight=1)
        
        ttk.Label(options_frame, text="Sleep Interval (seconds):").grid(row=0, column=0, sticky=tk.W, pady=3)
        self.retry_sleep = ttk.Entry(options_frame, width=10)
        self.retry_sleep.grid(row=0, column=1, sticky=tk.W, pady=3)
        self.retry_sleep.bind('<KeyRelease>', lambda e: self.save_settings())
        ttk.Label(options_frame, text="(default: 11)").grid(row=0, column=2, sticky=tk.W, padx=5)
        
        ttk.Label(options_frame, text="Format:").grid(row=1, column=0, sticky=tk.W, pady=3)
        self.retry_format = ttk.Combobox(options_frame, values=["mp3", "m4a", "opus", "flac", "wav", "mp4", "webm", "mkv"], width=10)
        self.retry_format.grid(row=1, column=1, sticky=tk.W, pady=3)
        self.retry_format.bind('<<ComboboxSelected>>', lambda e: self.save_settings())
        
        ttk.Label(options_frame, text="Quality:").grid(row=1, column=2, sticky=tk.W, pady=3, padx=10)
        self.retry_quality = ttk.Combobox(options_frame, values=["low", "mid", "high"], width=8)
        self.retry_quality.grid(row=1, column=3, sticky=tk.W, pady=3)
        self.retry_quality.bind('<<ComboboxSelected>>', lambda e: self.save_settings())
        
        ttk.Button(options_frame, text="Load Settings from Folder", command=lambda: self.load_config_from_folder(self.retry_output.get())).grid(row=2, column=2, columnspan=2, sticky=tk.E, pady=3)
        
        progress_frame = ttk.LabelFrame(main_frame, text="Progress", padding="8")
        progress_frame.grid(row=4, column=0, columnspan=4, sticky=tk.W+tk.E+tk.N+tk.S, pady=5)
        progress_frame.columnconfigure(0, weight=1)
        progress_frame.rowconfigure(1, weight=1)
        
        self.retry_progress = ttk.Progressbar(progress_frame, mode='indeterminate')
        self.retry_progress.grid(row=0, column=0, sticky=tk.W+tk.E, pady=3)
        
        self.retry_status = scrolledtext.ScrolledText(progress_frame, height=10, width=80)
        self.retry_status.grid(row=1, column=0, sticky=tk.W+tk.E+tk.N+tk.S, pady=3)
        
        main_frame.rowconfigure(4, weight=1)
        
        button_frame = ttk.Frame(main_frame)
        button_frame.grid(row=5, column=0, columnspan=4, pady=8)
        
        self.retry_btn = ttk.Button(button_frame, text="Start Retry", command=lambda: self.run_script("retry"))
        self.retry_btn.pack(side=tk.LEFT, padx=5)
        
        ttk.Button(button_frame, text="Stop", command=self.stop_current_download).pack(side=tk.LEFT, padx=5)
        ttk.Button(button_frame, text="Clear Output", command=lambda: self.retry_status.delete(1.0, tk.END)).pack(side=tk.LEFT, padx=5)
    
    def setup_move_tab(self):
        """Setup the Move Recovered tab"""
        main_frame = ttk.Frame(self.move_tab, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)
        main_frame.columnconfigure(1, weight=1)
        
        ttk.Label(main_frame, text="Working Directory:").grid(row=0, column=0, sticky=tk.W, pady=3)
        self.move_output = ttk.Entry(main_frame, width=70)
        self.move_output.grid(row=0, column=1, sticky=tk.W+tk.E, pady=3)
        self.move_output.bind('<KeyRelease>', lambda e: self.save_settings())
        ttk.Button(main_frame, text="Browse", command=lambda: self.browse_folder(self.move_output)).grid(row=0, column=2, padx=3)
        ttk.Button(main_frame, text="Use Current", command=lambda: self.set_current_path(self.move_output)).grid(row=0, column=3, padx=3)
        
        ttk.Label(main_frame, text="Note: All logs and settings are stored in '.TakData' subfolder", foreground="gray").grid(row=1, column=0, columnspan=4, sticky=tk.W, pady=2)
        
        ttk.Separator(main_frame, orient='horizontal').grid(row=2, column=0, columnspan=4, sticky=tk.W+tk.E, pady=5)
        
        options_frame = ttk.LabelFrame(main_frame, text="Options", padding="8")
        options_frame.grid(row=3, column=0, columnspan=4, sticky=tk.W+tk.E, pady=5)
        options_frame.columnconfigure(1, weight=0)
        options_frame.columnconfigure(3, weight=1)
        
        ttk.Label(options_frame, text="Target Format:").grid(row=0, column=0, sticky=tk.W, pady=3)
        self.move_format = ttk.Combobox(options_frame, values=["mp3", "m4a", "opus", "flac", "wav", "mp4", "webm", "mkv"], width=10)
        self.move_format.grid(row=0, column=1, sticky=tk.W, pady=3)
        self.move_format.bind('<<ComboboxSelected>>', lambda e: self.save_settings())
        
        ttk.Label(options_frame, text="Quality:").grid(row=0, column=2, sticky=tk.W, pady=3, padx=10)
        self.move_quality = ttk.Combobox(options_frame, values=["low", "mid", "high"], width=8)
        self.move_quality.grid(row=0, column=3, sticky=tk.W, pady=3)
        self.move_quality.bind('<<ComboboxSelected>>', lambda e: self.save_settings())
        
        ttk.Button(options_frame, text="Load Settings from Folder", command=lambda: self.load_config_from_folder(self.move_output.get())).grid(row=1, column=2, columnspan=2, sticky=tk.E, pady=3)
        
        progress_frame = ttk.LabelFrame(main_frame, text="Progress", padding="8")
        progress_frame.grid(row=4, column=0, columnspan=4, sticky=tk.W+tk.E+tk.N+tk.S, pady=5)
        progress_frame.columnconfigure(0, weight=1)
        progress_frame.rowconfigure(1, weight=1)
        
        self.move_progress = ttk.Progressbar(progress_frame, mode='indeterminate')
        self.move_progress.grid(row=0, column=0, sticky=tk.W+tk.E, pady=3)
        
        self.move_status = scrolledtext.ScrolledText(progress_frame, height=10, width=80)
        self.move_status.grid(row=1, column=0, sticky=tk.W+tk.E+tk.N+tk.S, pady=3)
        
        main_frame.rowconfigure(4, weight=1)
        
        button_frame = ttk.Frame(main_frame)
        button_frame.grid(row=5, column=0, columnspan=4, pady=8)
        
        self.move_btn = ttk.Button(button_frame, text="Start Move/Convert", command=lambda: self.run_script("move"))
        self.move_btn.pack(side=tk.LEFT, padx=5)
        
        ttk.Button(button_frame, text="Stop", command=self.stop_current_download).pack(side=tk.LEFT, padx=5)
        ttk.Button(button_frame, text="Clear Output", command=lambda: self.move_status.delete(1.0, tk.END)).pack(side=tk.LEFT, padx=5)
    
    def setup_scheduler_tab(self):
        """Setup the Scheduler tab with multiple tasks support"""
        main_frame = ttk.Frame(self.scheduler_tab, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Left panel - Task list
        left_panel = ttk.Frame(main_frame)
        left_panel.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 5))
        
        ttk.Label(left_panel, text="Scheduled Tasks", font=('TkDefaultFont', 10, 'bold')).pack(anchor=tk.W, pady=5)
        
        # Task list frame with scrollbar
        task_list_frame = ttk.Frame(left_panel)
        task_list_frame.pack(fill=tk.BOTH, expand=True)
        
        task_scrollbar = ttk.Scrollbar(task_list_frame)
        task_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        self.task_listbox = tk.Listbox(task_list_frame, yscrollcommand=task_scrollbar.set, height=15)
        self.task_listbox.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        task_scrollbar.config(command=self.task_listbox.yview)
        
        self.task_listbox.bind('<<ListboxSelect>>', self.on_task_select)
        
        # Task buttons
        task_btn_frame = ttk.Frame(left_panel)
        task_btn_frame.pack(fill=tk.X, pady=5)
        
        ttk.Button(task_btn_frame, text="Add Task", command=self.show_add_task_dialog).pack(side=tk.LEFT, padx=2)
        ttk.Button(task_btn_frame, text="Edit Task", command=self.show_edit_task_dialog).pack(side=tk.LEFT, padx=2)
        ttk.Button(task_btn_frame, text="Delete Task", command=self.delete_task).pack(side=tk.LEFT, padx=2)
        ttk.Button(task_btn_frame, text="Run Now", command=self.run_task_now).pack(side=tk.LEFT, padx=2)
        ttk.Button(task_btn_frame, text="Reset Interrupted", command=self.reset_interrupted_task).pack(side=tk.LEFT, padx=2)

        # Enable/Disable toggle
        self.enable_task_var = tk.BooleanVar()
        ttk.Checkbutton(left_panel, text="Task Enabled", variable=self.enable_task_var, command=self.toggle_task_enabled).pack(anchor=tk.W, pady=5)
        
        # Right panel - Task details and logs
        right_panel = ttk.Frame(main_frame)
        right_panel.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True, padx=(5, 0))
        
        # Task details frame
        details_frame = ttk.LabelFrame(right_panel, text="Task Details", padding="8")
        details_frame.pack(fill=tk.X, pady=5)
        
        self.details_text = scrolledtext.ScrolledText(details_frame, height=8, width=50)
        self.details_text.pack(fill=tk.BOTH, expand=True)
        
        # Task logs frame
        logs_frame = ttk.LabelFrame(right_panel, text="Task Logs", padding="8")
        logs_frame.pack(fill=tk.BOTH, expand=True, pady=5)
        
        self.task_logs = scrolledtext.ScrolledText(logs_frame, height=10, width=50)
        self.task_logs.pack(fill=tk.BOTH, expand=True)
        
        # Global scheduler controls
        scheduler_control_frame = ttk.Frame(right_panel)
        scheduler_control_frame.pack(fill=tk.X, pady=5)
        
        self.start_scheduler_btn = ttk.Button(scheduler_control_frame, text="Start Global Scheduler", command=self.start_global_scheduler)
        self.start_scheduler_btn.pack(side=tk.LEFT, padx=5)
        
        self.stop_scheduler_btn = ttk.Button(scheduler_control_frame, text="Stop Global Scheduler", command=self.stop_global_scheduler, state=tk.DISABLED)
        self.stop_scheduler_btn.pack(side=tk.LEFT, padx=5)
        
        self.scheduler_status_label = ttk.Label(scheduler_control_frame, text="Scheduler: Stopped", foreground="red")
        self.scheduler_status_label.pack(side=tk.LEFT, padx=10)
    
    def setup_settings_tab(self):
        """Setup the Settings tab"""
        main_frame = ttk.Frame(self.settings_tab, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)
        main_frame.columnconfigure(1, weight=1)
        
        ttk.Label(main_frame, text="Scripts Directory:").grid(row=0, column=0, sticky=tk.W, pady=5)
        self.scripts_dir_var = tk.StringVar(value=str(self.script_dir))
        scripts_entry = ttk.Entry(main_frame, textvariable=self.scripts_dir_var, width=70)
        scripts_entry.grid(row=0, column=1, sticky=tk.W+tk.E, pady=5)
        scripts_entry.bind('<KeyRelease>', lambda e: self.save_settings())
        ttk.Button(main_frame, text="Browse", command=self.browse_scripts_dir).grid(row=0, column=2, padx=5)
        
        ttk.Separator(main_frame, orient='horizontal').grid(row=1, column=0, columnspan=3, sticky=tk.W+tk.E, pady=10)
        
        # Autostart frame
        autostart_frame = ttk.LabelFrame(main_frame, text="Autostart", padding="10")
        autostart_frame.grid(row=2, column=0, columnspan=3, sticky=tk.W+tk.E, pady=5)
        
        self.autostart_var = tk.BooleanVar(value=self.is_autostart_enabled())
        ttk.Checkbutton(autostart_frame, text="Start Tak Playlist Downloader automatically when computer starts",
                        variable=self.autostart_var, command=self.toggle_autostart).pack(anchor=tk.W, pady=5)
        
        ttk.Label(autostart_frame, text="Note: The app will start minimized to system tray (Windows) or in background (Linux)",
                  foreground="gray").pack(anchor=tk.W, pady=2)
        
        # Dark mode frame
        darkmode_frame = ttk.LabelFrame(main_frame, text="Appearance", padding="10")
        darkmode_frame.grid(row=3, column=0, columnspan=3, sticky=tk.W+tk.E, pady=5)
        
        ttk.Checkbutton(darkmode_frame, text="Dark Mode", variable=self.dark_mode,
                        command=self.toggle_dark_mode).pack(anchor=tk.W, pady=5)
        
        # System tray info
        tray_frame = ttk.LabelFrame(main_frame, text="System Tray", padding="10")
        tray_frame.grid(row=4, column=0, columnspan=3, sticky=tk.W+tk.E, pady=5)
        
        if PYSTRAY_AVAILABLE:
            ttk.Label(tray_frame, text="✓ System tray support enabled", foreground="green").pack(anchor=tk.W, pady=2)
            ttk.Label(tray_frame, text="  • Close window (X) minimizes to tray").pack(anchor=tk.W, pady=2)
            ttk.Label(tray_frame, text="  • Click tray icon and select 'Show' to restore").pack(anchor=tk.W, pady=2)
            ttk.Label(tray_frame, text="  • Select 'Quit' from tray menu to exit completely").pack(anchor=tk.W, pady=2)
        else:
            ttk.Label(tray_frame, text="✗ System tray support not available", foreground="red").pack(anchor=tk.W, pady=2)
            ttk.Label(tray_frame, text="  Install with: pip install pystray pillow", foreground="gray").pack(anchor=tk.W, pady=2)
        
        # Config location info
        info_frame = ttk.LabelFrame(main_frame, text="Configuration", padding="10")
        info_frame.grid(row=5, column=0, columnspan=3, sticky=tk.W+tk.E, pady=5)
        
        ttk.Label(info_frame, text=f"Settings saved to: {self.settings_file}").pack(anchor=tk.W, pady=2)
        ttk.Label(info_frame, text="Settings are automatically saved when you change any field").pack(anchor=tk.W, pady=2)
        ttk.Label(info_frame, text="Scheduled tasks saved to: {self.tasks_file}").pack(anchor=tk.W, pady=2)
        
        # System info
        sys_frame = ttk.LabelFrame(main_frame, text="System Information", padding="10")
        sys_frame.grid(row=6, column=0, columnspan=3, sticky=tk.W+tk.E, pady=5)
        
        ttk.Label(sys_frame, text=f"Operating System: {self.os_type}").pack(anchor=tk.W, pady=2)
        ttk.Label(sys_frame, text=f"Script Extension: {self.script_ext}").pack(anchor=tk.W, pady=2)
        ttk.Label(sys_frame, text=f"Python Version: {sys.version.split()[0]}").pack(anchor=tk.W, pady=2)
        
        # About
        about_frame = ttk.LabelFrame(main_frame, text="About", padding="10")
        about_frame.grid(row=7, column=0, columnspan=3, sticky=tk.W+tk.E, pady=5)
        
        about_text = """Tak Playlist Downloader
A cross-platform graphical interface for downloading YouTube playlists.

Features:
- Download entire playlists as MP3/MP4
- Archive recovery for deleted videos
- Retry failed downloads
- Convert recovered files
- Schedule multiple automatic downloads
- Settings automatically saved
- Dark mode support
- Autostart support
- System tray support
- All logs stored in '.TakData' subfolder

Scripts required in the same directory:
- Download-Playlist.ps1/.sh
- Retry-Failed.ps1/.sh
- Move-Recovered.ps1/.sh"""
        
        about_label = ttk.Label(about_frame, text=about_text, justify=tk.LEFT)
        about_label.pack(anchor=tk.W, pady=5)
    
    def setup_tray(self):
        """Setup system tray icon and menu"""
        if not PYSTRAY_AVAILABLE:
            return
        
        try:
            def create_icon_image():
                width = 64
                height = 64
                # Use different colors based on dark mode
                if self.dark_mode.get():
                    bg_color = (33, 33, 33)
                else:
                    bg_color = (33, 150, 243)
                image = Image.new('RGB', (width, height), bg_color)
                draw = ImageDraw.Draw(image)
                points = [(24, 16), (24, 48), (48, 32)]
                draw.polygon(points, fill=(255, 255, 255))
                return image
            
            def on_show():
                self.root.after(0, self.restore_from_tray)
            
            def on_quit():
                self.root.after(0, self.quit_application)
            
            self.tray_icon = pystray.Icon(
                "tak_downloader",
                create_icon_image(),
                "Tak Playlist Downloader",
                menu=pystray.Menu(
                    pystray.MenuItem("Show", on_show, default=True),
                    pystray.MenuItem("Quit", on_quit)
                )
            )
        except Exception as e:
            print(f"Warning: Could not create tray icon: {e}")
            self.tray_icon = None
    
    def minimize_to_tray(self):
        """Minimize the application to system tray"""
        if not PYSTRAY_AVAILABLE or not self.tray_icon:
            self.root.iconify()
            return
        
        if self.minimized_to_tray:
            return
        
        self.minimized_to_tray = True
        self.root.withdraw()
        
        if self.tray_icon and not getattr(self.tray_icon, '_running', False):
            def run_tray():
                try:
                    self.tray_icon.run()
                except Exception as e:
                    print(f"Tray icon error: {e}")
            
            self.tray_thread = threading.Thread(target=run_tray, daemon=True)
            self.tray_thread.start()
    
    def restore_from_tray(self):
        """Restore the application from system tray"""
        self.minimized_to_tray = False
        self.root.deiconify()
        self.root.lift()
        self.root.focus_force()
        
        if self.tray_icon:
            try:
                self.tray_icon.stop()
            except Exception:
                pass
            self.tray_icon = None
            self.root.after(100, self.setup_tray)
    
    def quit_application(self):
        """Properly quit the application"""
        self.minimized_to_tray = False
        self.save_settings()
        self.save_tasks()
        self.scheduler_running = False
        
        # Kill any running processes
        for task_id, task in self.tasks.items():
            if task.running and task.process:
                try:
                    task.process.terminate()
                except:
                    pass
        
        # Stop the tray icon if running
        if self.tray_icon:
            try:
                self.tray_icon.stop()
            except:
                pass
        
        # Quit the application
        self.root.quit()
        self.root.destroy()
        sys.exit(0)
    
    def cleanup(self):
        """Clean up running processes on exit"""
        self.scheduler_running = False
        for task_id, task in self.tasks.items():
            if task.running and task.process:
                try:
                    task.process.terminate()
                except:
                    pass
    
    # ... (rest of the methods remain the same as your original code)
    # The following methods should be kept as they were:
    # add_current_to_scheduler, show_add_task_dialog, browse_folder_dialog, 
    # generate_task_name, on_task_select, update_task_list, toggle_task_enabled,
    # delete_task, run_task_now, show_edit_task_dialog, is_within_time_window,
    # execute_task, build_task_command, update_task_next_run, add_task_log,
    # start_global_scheduler, stop_global_scheduler, _run_scheduler_loop,
    # check_and_start_scheduler, start_task_processor, _process_task_queue,
    # browse_scripts_dir, browse_folder, set_current_path, load_config_from_folder,
    # save_settings, save_tasks, load_tasks, load_settings, on_closing,
    # stop_current_download, update_status, build_download_command,
    # build_retry_command, build_move_command, run_script, execute_script

    def add_current_to_scheduler(self):
        """Add current download settings as a scheduled task"""
        if not self.download_url.get().strip():
            messagebox.showerror("Error", "Please enter a playlist URL first")
            return
        
        self.show_add_task_dialog(populate_from_current=True)
    
    def show_add_task_dialog(self, populate_from_current=False, edit_task=None):
        """Show dialog to add or edit a scheduled task"""
        dialog = tk.Toplevel(self.root)
        dialog.title("Add Scheduled Task" if not edit_task else "Edit Scheduled Task")
        dialog.geometry("550x650")
        dialog.transient(self.root)
        dialog.grab_set()
        
        # Create a canvas with scrollbar for the entire dialog content
        canvas = tk.Canvas(dialog)
        scrollbar = ttk.Scrollbar(dialog, orient="vertical", command=canvas.yview)
        scrollable_frame = ttk.Frame(canvas)
        
        scrollable_frame.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        # Mouse wheel scrolling
        def _on_mousewheel(event):
            canvas.yview_scroll(int(-1*(event.delta/120)), "units")
        canvas.bind_all("<MouseWheel>", _on_mousewheel)
        
        # Variables
        task_name = tk.StringVar()
        playlist_url = tk.StringVar()
        output_dir = tk.StringVar()
        schedule_type = tk.StringVar(value="days")
        interval = tk.StringVar(value="1")
        enable_time_window = tk.BooleanVar(value=False)
        start_hour = tk.StringVar(value="14")
        start_minute = tk.StringVar(value="00")
        end_hour = tk.StringVar(value="18")
        end_minute = tk.StringVar(value="00")
        enable_specific_time = tk.BooleanVar(value=False)
        specific_hour = tk.StringVar(value="05")
        specific_minute = tk.StringVar(value="00")
        format_type = tk.StringVar(value="mp3")
        quality = tk.StringVar(value="mid")
        enable_archive = tk.BooleanVar(value=False)
        
        if populate_from_current:
            playlist_url.set(self.download_url.get().strip())
            output_dir.set(self.download_output.get().strip())
            format_type.set(self.download_format.get())
            quality.set(self.download_quality.get())
            enable_archive.set(self.download_archive.get())
            task_name.set(self.generate_task_name())
        
        if edit_task:
            task_id = edit_task.id
            task_name.set(edit_task.name)
            playlist_url.set(edit_task.playlist_url)
            output_dir.set(edit_task.output_dir)
            schedule_type.set(edit_task.schedule_type)
            interval.set(str(edit_task.interval))
            enable_time_window.set(edit_task.enable_time_window)
            start_hour.set(edit_task.start_hour)
            start_minute.set(edit_task.start_minute)
            end_hour.set(edit_task.end_hour)
            end_minute.set(edit_task.end_minute)
            enable_specific_time.set(edit_task.enable_specific_time)
            specific_hour.set(edit_task.specific_hour)
            specific_minute.set(edit_task.specific_minute)
            format_type.set(edit_task.format)
            quality.set(edit_task.quality)
            enable_archive.set(edit_task.enable_archive)
        
        row = 0
        
        # Task name
        ttk.Label(scrollable_frame, text="Task Name:").grid(row=row, column=0, sticky=tk.W, padx=10, pady=5)
        name_entry = ttk.Entry(scrollable_frame, textvariable=task_name, width=50)
        name_entry.grid(row=row, column=1, sticky=tk.W+tk.E, padx=10, pady=5)
        row += 1
        
        # Playlist URL
        ttk.Label(scrollable_frame, text="Playlist URL:").grid(row=row, column=0, sticky=tk.W, padx=10, pady=5)
        url_entry = ttk.Entry(scrollable_frame, textvariable=playlist_url, width=50)
        url_entry.grid(row=row, column=1, sticky=tk.W+tk.E, padx=10, pady=5)
        row += 1
        
        # Output Directory
        ttk.Label(scrollable_frame, text="Output Directory:").grid(row=row, column=0, sticky=tk.W, padx=10, pady=5)
        output_frame = ttk.Frame(scrollable_frame)
        output_frame.grid(row=row, column=1, sticky=tk.W+tk.E, padx=10, pady=5)
        output_entry = ttk.Entry(output_frame, textvariable=output_dir)
        output_entry.pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(output_frame, text="Browse", command=lambda: self.browse_folder_dialog(output_dir)).pack(side=tk.RIGHT, padx=5)
        row += 1
        
        # Schedule settings frame
        schedule_frame = ttk.LabelFrame(scrollable_frame, text="Schedule Settings", padding="10")
        schedule_frame.grid(row=row, column=0, columnspan=2, sticky=tk.W+tk.E, padx=10, pady=10)
        row += 1
        
        # Schedule type and interval
        ttk.Label(schedule_frame, text="Schedule Type:").grid(row=0, column=0, sticky=tk.W, pady=3)
        type_combo = ttk.Combobox(schedule_frame, textvariable=schedule_type, values=["minutes", "hours", "days", "weeks", "months"], width=10)
        type_combo.grid(row=0, column=1, sticky=tk.W, pady=3)
        
        ttk.Label(schedule_frame, text="Interval:").grid(row=0, column=2, sticky=tk.W, pady=3, padx=10)
        interval_entry = ttk.Entry(schedule_frame, textvariable=interval, width=8)
        interval_entry.grid(row=0, column=3, sticky=tk.W, pady=3)
        
        # Time window
        time_window_frame = ttk.LabelFrame(schedule_frame, text="Time Window (Optional)", padding="5")
        time_window_frame.grid(row=1, column=0, columnspan=4, sticky=tk.W+tk.E, pady=10)
        
        ttk.Checkbutton(time_window_frame, text="Enable Time Window", variable=enable_time_window).pack(anchor=tk.W)
        
        time_frame = ttk.Frame(time_window_frame)
        time_frame.pack(fill=tk.X, pady=5)
        
        ttk.Label(time_frame, text="Start:").pack(side=tk.LEFT, padx=5)
        ttk.Combobox(time_frame, textvariable=start_hour, values=[str(i).zfill(2) for i in range(24)], width=5).pack(side=tk.LEFT)
        ttk.Label(time_frame, text=":").pack(side=tk.LEFT)
        ttk.Combobox(time_frame, textvariable=start_minute, values=[str(i).zfill(2) for i in range(60)], width=5).pack(side=tk.LEFT)
        
        ttk.Label(time_frame, text="  End:").pack(side=tk.LEFT, padx=5)
        ttk.Combobox(time_frame, textvariable=end_hour, values=[str(i).zfill(2) for i in range(24)], width=5).pack(side=tk.LEFT)
        ttk.Label(time_frame, text=":").pack(side=tk.LEFT)
        ttk.Combobox(time_frame, textvariable=end_minute, values=[str(i).zfill(2) for i in range(60)], width=5).pack(side=tk.LEFT)
        
        # Specific time
        specific_frame = ttk.LabelFrame(schedule_frame, text="Specific Time (Optional)", padding="5")
        specific_frame.grid(row=2, column=0, columnspan=4, sticky=tk.W+tk.E, pady=10)
        
        ttk.Checkbutton(specific_frame, text="Run at Specific Time", variable=enable_specific_time).pack(anchor=tk.W)
        
        specific_time_frame = ttk.Frame(specific_frame)
        specific_time_frame.pack(fill=tk.X, pady=5)
        
        ttk.Label(specific_time_frame, text="Time:").pack(side=tk.LEFT, padx=5)
        ttk.Combobox(specific_time_frame, textvariable=specific_hour, values=[str(i).zfill(2) for i in range(24)], width=5).pack(side=tk.LEFT)
        ttk.Label(specific_time_frame, text=":").pack(side=tk.LEFT)
        ttk.Combobox(specific_time_frame, textvariable=specific_minute, values=[str(i).zfill(2) for i in range(60)], width=5).pack(side=tk.LEFT)
        
        # Download options frame
        options_frame = ttk.LabelFrame(scrollable_frame, text="Download Options", padding="10")
        options_frame.grid(row=row, column=0, columnspan=2, sticky=tk.W+tk.E, padx=10, pady=10)
        row += 1
        
        ttk.Label(options_frame, text="Format:").grid(row=0, column=0, sticky=tk.W, pady=3)
        format_combo = ttk.Combobox(options_frame, textvariable=format_type, values=["mp3", "m4a", "opus", "flac", "wav", "mp4", "webm", "mkv"], width=10)
        format_combo.grid(row=0, column=1, sticky=tk.W, pady=3)
        
        ttk.Label(options_frame, text="Quality:").grid(row=0, column=2, sticky=tk.W, pady=3, padx=10)
        quality_combo = ttk.Combobox(options_frame, textvariable=quality, values=["low", "mid", "high"], width=8)
        quality_combo.grid(row=0, column=3, sticky=tk.W, pady=3)
        
        ttk.Checkbutton(options_frame, text="Enable Archive Recovery", variable=enable_archive).grid(row=1, column=0, columnspan=4, sticky=tk.W, pady=5)
        
        # Buttons frame - at the bottom
        button_frame = ttk.Frame(scrollable_frame)
        button_frame.grid(row=row, column=0, columnspan=2, sticky=tk.W+tk.E, padx=10, pady=15)
        row += 1
        
        def save_task():
            if not task_name.get().strip():
                messagebox.showerror("Error", "Task name is required")
                return
            if not playlist_url.get().strip():
                messagebox.showerror("Error", "Playlist URL is required")
                return
            if not output_dir.get().strip():
                messagebox.showerror("Error", "Output directory is required")
                return
            
            try:
                interval_val = int(interval.get())
                if interval_val <= 0:
                    raise ValueError
            except ValueError:
                messagebox.showerror("Error", "Interval must be a positive number")
                return
            
            if edit_task:
                task_id = edit_task.id
                # Remove old task from scheduler if running
                if self.scheduler_running:
                    self.stop_global_scheduler()
            else:
                task_id = str(uuid.uuid4())
            
            task = ScheduledTask(
                task_id=task_id,
                name=task_name.get().strip(),
                playlist_url=playlist_url.get().strip(),
                output_dir=output_dir.get().strip(),
                schedule_type=schedule_type.get(),
                interval=interval_val,
                enable_time_window=enable_time_window.get(),
                start_hour=start_hour.get(),
                start_minute=start_minute.get(),
                end_hour=end_hour.get(),
                end_minute=end_minute.get(),
                enable_specific_time=enable_specific_time.get(),
                specific_hour=specific_hour.get(),
                specific_minute=specific_minute.get(),
                format_type=format_type.get(),
                quality=quality.get(),
                enable_archive=enable_archive.get(),
                enabled=True
            )
            
            self.tasks[task_id] = task
            self.save_tasks()
            self.update_task_list()
            
            dialog.destroy()
            
            # Restart scheduler if it was running
            if self.scheduler_running:
                self.start_global_scheduler()
        
        ttk.Button(button_frame, text="Save Task", command=save_task).pack(side=tk.LEFT, padx=5)
        ttk.Button(button_frame, text="Cancel", command=dialog.destroy).pack(side=tk.LEFT, padx=5)
        
        # Configure grid weights for scrollable frame
        scrollable_frame.columnconfigure(1, weight=1)
    
    def browse_folder_dialog(self, string_var):
        """Browse folder for dialog"""
        folder = filedialog.askdirectory(initialdir=self.current_browse_dir)
        if folder:
            string_var.set(folder)
            self.current_browse_dir = folder
    
    def generate_task_name(self):
        """Generate a default task name based on playlist URL"""
        url = self.download_url.get().strip()
        # Extract playlist ID or use timestamp
        if "list=" in url:
            list_part = url.split("list=")[1].split("&")[0]
            name = f"Playlist_{list_part[:16]}"
        else:
            name = f"Task_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        return name
    
    def on_task_select(self, event):
        """Handle task selection from listbox"""
        selection = self.task_listbox.curselection()
        if not selection:
            return
        
        task_id = self.task_listbox.get(selection[0]).split(" - ")[0]
        task = self.tasks.get(task_id)
        if not task:
            return
        
        # Update details text
        self.details_text.delete(1.0, tk.END)
        details = f"""Name: {task.name}
    Playlist URL: {task.playlist_url}
    Output Directory: {task.output_dir}
    Schedule: Every {task.interval} {task.schedule_type}
    """
        if task.enable_specific_time:
            details += f"Specific Time: {task.specific_hour}:{task.specific_minute}\n"
        if task.enable_time_window:
            details += f"Time Window: {task.start_hour}:{task.start_minute} - {task.end_hour}:{task.end_minute}\n"
        details += f"""Format: {task.format}
    Quality: {task.quality}
    Archive Recovery: {'Yes' if task.enable_archive else 'No'}
    Enabled: {'Yes' if task.enabled else 'No'}
    Last Run: {task.last_run if task.last_run else 'Never'}
    """
        
        # Add progress information
        if task.interrupted and task.remaining_downloads is not None:
            details += f"\n⚠️ Last run was interrupted! {task.remaining_downloads} videos remaining.\n"
            details += f"   Will resume on next scheduled run.\n"
        elif task.running:
            details += f"\n🟢 Currently running...\n"
        elif task.last_completion_time:
            try:
                last = datetime.fromisoformat(task.last_completion_time)
                if not task.enable_specific_time:
                    next_run = task.get_next_interval_run_time()
                    details += f"\nNext run will be approximately: {next_run.strftime('%Y-%m-%d %H:%M:%S')}\n"
            except:
                pass
        
        self.details_text.insert(1.0, details)
        
        # Update enable checkbox
        self.enable_task_var.set(task.enabled)
    
    def update_task_list(self):
        """Update the task listbox"""
        self.task_listbox.delete(0, tk.END)
        for task_id, task in self.tasks.items():
            status = "✓" if task.enabled else "✗"
            self.task_listbox.insert(tk.END, f"{task_id} - {status} {task.name}")
    
    def toggle_task_enabled(self):
        """Enable or disable selected task"""
        selection = self.task_listbox.curselection()
        if not selection:
            return
        
        task_id = self.task_listbox.get(selection[0]).split(" - ")[0]
        task = self.tasks.get(task_id)
        if task:
            task.enabled = self.enable_task_var.get()
            self.save_tasks()
            self.update_task_list()
            
            # Restart scheduler to apply changes
            if self.scheduler_running:
                self.stop_global_scheduler()
                self.start_global_scheduler()
    
    def delete_task(self):
        """Delete selected task"""
        selection = self.task_listbox.curselection()
        if not selection:
            return
        
        task_id = self.task_listbox.get(selection[0]).split(" - ")[0]
        if messagebox.askyesno("Confirm Delete", f"Delete task '{self.tasks[task_id].name}'?"):
            del self.tasks[task_id]
            self.save_tasks()
            self.update_task_list()
            self.details_text.delete(1.0, tk.END)
            
            # Restart scheduler if running
            if self.scheduler_running:
                self.stop_global_scheduler()
                self.start_global_scheduler()
    
    def run_task_now(self):
        """Run selected task immediately"""
        selection = self.task_listbox.curselection()
        if not selection:
            return
        
        task_id = self.task_listbox.get(selection[0]).split(" - ")[0]
        task = self.tasks.get(task_id)
        if task:
            self.execute_task(task)

    def reset_interrupted_task(self):
        """Reset an interrupted task so it starts fresh next time"""
        selection = self.task_listbox.curselection()
        if not selection:
            return
        
        task_id = self.task_listbox.get(selection[0]).split(" - ")[0]
        task = self.tasks.get(task_id)
        if task and messagebox.askyesno("Confirm Reset", f"Reset '{task.name}'?\n\nThis will clear the interrupted state and the task will start fresh on next run."):
            task.interrupted = False
            task.remaining_downloads = None
            task.last_completion_time = None
            self.save_tasks()
            self.on_task_select(None)  # Refresh display
            self.add_task_log(task_id, f"RESET: {task.name} - Interrupted state cleared")
    
    def show_edit_task_dialog(self):
        """Show edit dialog for selected task"""
        selection = self.task_listbox.curselection()
        if not selection:
            return
        
        task_id = self.task_listbox.get(selection[0]).split(" - ")[0]
        task = self.tasks.get(task_id)
        if task:
            self.show_add_task_dialog(edit_task=task)
    
    def is_within_time_window(self, task):
        """Check if current time is within task's time window"""
        if not task.enable_time_window:
            return True
        
        now = datetime.now()
        current = now.time()
        
        start = time(int(task.start_hour), int(task.start_minute))
        end = time(int(task.end_hour), int(task.end_minute))
        
        if start <= end:
            return start <= current <= end
        else:
            return current >= start or current <= end
    
    def execute_task(self, task):
        """Execute a scheduled task"""
        if task.running:
            self.add_task_log(task.id, f"SKIP: {task.name} - Already running")
            return
        
        if not self.is_within_time_window(task):
            self.add_task_log(task.id, f"SKIP: {task.name} - Outside time window")
            return
        
        # For interval-based tasks, check if it's time to run based on last completion
        if not task.enable_specific_time:
            next_run = task.get_next_interval_run_time()
            if next_run > datetime.now():
                # Not time yet, reschedule
                delay = (next_run - datetime.now()).total_seconds()
                timer = threading.Timer(delay, self._execute_wrapper, args=[task, False])
                timer.daemon = True
                timer.start()
                self.scheduled_timers.append(timer)
                return
        
        task.running = True
        task.last_start_time = datetime.now().isoformat()
        
        # Track if this is a resume (was interrupted)
        is_resume = task.interrupted and task.remaining_downloads is not None
        
        if is_resume:
            self.add_task_log(task.id, f"RESUME: {task.name} - Resuming from previous run")
            task.interrupted = False
        else:
            self.add_task_log(task.id, f"START: {task.name}")
        
        self.save_tasks()
        
        def run_task():
            try:
                cmd = self.build_task_command(task)
                if not cmd:
                    self.add_task_log(task.id, f"ERROR: {task.name} - Failed to build command")
                    task.running = False
                    return
                
                process_flags = {}
                if self.os_type == "Windows":
                    process_flags['creationflags'] = subprocess.CREATE_NO_WINDOW
                
                task.process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    universal_newlines=True,
                    cwd=str(self.script_dir),
                    **process_flags
                )
                
                for line in task.process.stdout:
                    clean_line = strip_ansi_codes(line).strip()
                    if clean_line:
                        self.add_task_log(task.id, clean_line)
                        
                        # Track progress
                        progress_match = re.search(r'\[(\d+)/(\d+)\]', clean_line)
                        if progress_match:
                            current = int(progress_match.group(1))
                            total = int(progress_match.group(2))
                            task.remaining_downloads = total - current
                            self.save_tasks()
                
                return_code = task.process.wait()
                task.process = None
                
                if return_code == 0:
                    task.last_completion_time = datetime.now().isoformat()
                    task.remaining_downloads = None
                    task.interrupted = False
                    task.last_run = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    self.add_task_log(task.id, f"COMPLETE: {task.name}")
                else:
                    task.interrupted = True
                    self.add_task_log(task.id, f"INTERRUPTED: {task.name} (exit code: {return_code})")
                
                self.save_tasks()
                
            except Exception as e:
                task.interrupted = True
                self.add_task_log(task.id, f"ERROR: {task.name} - {str(e)}")
                self.save_tasks()
            finally:
                task.running = False
                # The task will be rescheduled by the wrapper if needed
        
        thread = threading.Thread(target=run_task, daemon=True)
        thread.start()
    
    def build_task_command(self, task, resume=False):
        """Build command for a scheduled task"""
        script_path = self.script_dir / f"Download-Playlist{self.script_ext}"
        
        if not script_path.exists():
            return None
        
        cmd = []
        if self.os_type == "Windows":
            cmd = ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", str(script_path)]
        else:
            cmd = ["/bin/bash", str(script_path)]
        
        cmd.extend(["-p", task.playlist_url])
        cmd.extend(["-o", task.output_dir])
        cmd.extend(["-t", str(11)])  # Default sleep interval
        cmd.extend(["-f", task.format])
        cmd.extend(["-q", task.quality])
        
        if task.enable_archive:
            cmd.append("-a")
        
        # Note: Resume functionality is handled by the script's own resume capability
        # (it checks for existing .TakData files)
        
        return cmd
    
    def update_task_next_run(self, task):
        """Update the next run time for a task"""
        # This is calculated by the schedule library
        pass
    
    def add_task_log(self, task_id, message):
        """Add a log entry for a task"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        log_entry = f"[{timestamp}] {message}\n"
        
        def _update():
            self.task_logs.insert(tk.END, log_entry)
            self.task_logs.see(tk.END)
        self.root.after(0, _update)
    
    def start_global_scheduler(self):
        """Start the global scheduler to run all enabled tasks"""
        if self.scheduler_running:
            self.stop_global_scheduler()
        
        self.scheduler_running = True
        self.scheduled_timers = []
        
        for task_id, task in self.tasks.items():
            if not task.enabled:
                continue
            
            if task.enable_specific_time:
                self._schedule_specific_time_task(task)
            else:
                self._schedule_interval_task(task)
        
        self.scheduler_status_label.config(text="Scheduler: RUNNING", foreground="green")
        self.start_scheduler_btn.config(text="▶ Running", state=tk.DISABLED)
        self.stop_scheduler_btn.config(text="⏹ Stop", state=tk.NORMAL)

    def _schedule_specific_time_task(self, task):
        """Schedule a task at a specific time of day"""
        now = datetime.now()
        target_time = now.replace(hour=int(task.specific_hour), minute=int(task.specific_minute), second=0, microsecond=0)
        
        if target_time <= now:
            target_time += timedelta(days=1)
        
        delay_seconds = (target_time - now).total_seconds()
        
        def run_and_reschedule():
            if not self.scheduler_running:
                return
            
            # Execute the task
            self._execute_and_reschedule(task, is_specific=True)
        
        timer = threading.Timer(delay_seconds, run_and_reschedule)
        timer.daemon = True
        timer.start()
        self.scheduled_timers.append(timer)
        
        self.add_task_log(task.id, f"SCHEDULED: {task.name} at {task.specific_hour}:{task.specific_minute} (in {int(delay_seconds/60)} minutes)")

    def _schedule_interval_task(self, task):
        """Schedule an interval-based task based on last completion time"""
        now = datetime.now()
        next_run = task.get_next_interval_run_time()
        
        # If next_run is None or in the past, run immediately
        if next_run is None or next_run <= now:
            self.add_task_log(task.id, f"STARTING: {task.name} - Running now")
            threading.Thread(target=self._execute_and_reschedule, args=(task, False), daemon=True).start()
            return
        
        delay_seconds = (next_run - now).total_seconds()
        
        def run_and_reschedule():
            if not self.scheduler_running:
                return
            self._execute_and_reschedule(task, is_specific=False)
        
        timer = threading.Timer(delay_seconds, run_and_reschedule)
        timer.daemon = True
        timer.start()
        self.scheduled_timers.append(timer)
        
        # Format delay for display
        if delay_seconds < 60:
            self.add_task_log(task.id, f"SCHEDULED: {task.name} every {task.interval} {task.schedule_type} (in {int(delay_seconds)} seconds)")
        elif delay_seconds < 3600:
            self.add_task_log(task.id, f"SCHEDULED: {task.name} every {task.interval} {task.schedule_type} (in {int(delay_seconds/60)} minutes)")
        else:
            self.add_task_log(task.id, f"SCHEDULED: {task.name} every {task.interval} {task.schedule_type} (in {int(delay_seconds/3600)} hours)")

    def _execute_and_reschedule(self, task, is_specific):
        """Execute a task and then reschedule it for its next run"""
        if not self.scheduler_running:
            return
        
        # Check if task is already running
        if task.running:
            self.add_task_log(task.id, f"SKIP: {task.name} - Already running")
            # Reschedule anyway
            if is_specific:
                self._schedule_specific_time_task(task)
            else:
                self._schedule_interval_task(task)
            return
        
        # Check time window
        if not self.is_within_time_window(task):
            self.add_task_log(task.id, f"SKIP: {task.name} - Outside time window")
            # Reschedule for next interval
            if is_specific:
                self._schedule_specific_time_task(task)
            else:
                self._schedule_interval_task(task)
            return
        
        # Run the task
        self.execute_task(task, is_specific)

    def execute_task(self, task, is_specific):
        """Execute a scheduled task"""
        task.running = True
        task.last_start_time = datetime.now().isoformat()
        
        is_resume = task.interrupted and task.remaining_downloads is not None
        
        if is_resume:
            self.add_task_log(task.id, f"RESUME: {task.name}")
            task.interrupted = False
        else:
            self.add_task_log(task.id, f"START: {task.name}")
        
        self.save_tasks()
        
        def run_task():
            try:
                cmd = self.build_task_command(task)
                if not cmd:
                    self.add_task_log(task.id, f"ERROR: {task.name} - Failed to build command")
                    task.running = False
                    self._schedule_next_after_completion(task, is_specific)
                    return
                
                process_flags = {}
                if self.os_type == "Windows":
                    process_flags['creationflags'] = subprocess.CREATE_NO_WINDOW
                
                task.process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    universal_newlines=True,
                    cwd=str(self.script_dir),
                    **process_flags
                )
                
                for line in task.process.stdout:
                    clean_line = strip_ansi_codes(line).strip()
                    if clean_line:
                        self.add_task_log(task.id, clean_line)
                        
                        # Track progress
                        progress_match = re.search(r'\[(\d+)/(\d+)\]', clean_line)
                        if progress_match:
                            current = int(progress_match.group(1))
                            total = int(progress_match.group(2))
                            task.remaining_downloads = total - current
                            self.save_tasks()
                
                return_code = task.process.wait()
                task.process = None
                
                if return_code == 0:
                    task.last_completion_time = datetime.now().isoformat()
                    task.remaining_downloads = None
                    task.interrupted = False
                    task.last_run = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    self.add_task_log(task.id, f"COMPLETE: {task.name}")
                else:
                    task.interrupted = True
                    self.add_task_log(task.id, f"INTERRUPTED: {task.name} (exit code: {return_code})")
                
                self.save_tasks()
                
            except Exception as e:
                task.interrupted = True
                self.add_task_log(task.id, f"ERROR: {task.name} - {str(e)}")
                self.save_tasks()
            finally:
                task.running = False
                self._schedule_next_after_completion(task, is_specific)
        
        thread = threading.Thread(target=run_task, daemon=True)
        thread.start()

    def _schedule_next_after_completion(self, task, is_specific):
        """Schedule the next run after a task completes"""
        if not self.scheduler_running or not task.enabled:
            return
        
        if is_specific:
            # For specific time, schedule for next day
            self._schedule_specific_time_task(task)
        else:
            # For interval tasks, schedule based on completion time
            # Update the last_completion_time to now for interval calculation
            task.last_completion_time = datetime.now().isoformat()
            self.save_tasks()
            self._schedule_interval_task(task)

    def stop_global_scheduler(self):
        """Stop the global scheduler"""
        self.scheduler_running = False
        
        # Cancel all pending timers
        for timer in self.scheduled_timers:
            try:
                timer.cancel()
            except:
                pass
        self.scheduled_timers = []
        
        self.scheduler_status_label.config(text="Scheduler: STOPPED", foreground="red")
        self.start_scheduler_btn.config(text="▶ Start", state=tk.NORMAL)
        self.stop_scheduler_btn.config(text="⏹ Stop", state=tk.DISABLED)
    
    def check_and_start_scheduler(self):
        """Check if there are enabled tasks and start scheduler"""
        enabled_tasks = [t for t in self.tasks.values() if t.enabled]
        if enabled_tasks:
            self.start_global_scheduler()
    
    def start_task_processor(self):
        """Start background task processor"""
        self._task_processor_running = True
        self._task_processor_thread = threading.Thread(target=self._process_task_queue, daemon=True)
        self._task_processor_thread.start()
    
    def _process_task_queue(self):
        """Process tasks from queue"""
        while self._task_processor_running:
            try:
                task_func = self.task_queue.get(timeout=1)
                task_func()
            except:
                pass
    
    def browse_scripts_dir(self):
        """Browse for scripts directory"""
        folder = filedialog.askdirectory(initialdir=self.current_browse_dir)
        if folder:
            self.scripts_dir_var.set(folder)
            self.script_dir = Path(folder)
            self.current_browse_dir = folder
            self.save_settings()
    
    def browse_folder(self, entry_widget):
        """Browse for folder"""
        folder = filedialog.askdirectory(initialdir=self.current_browse_dir)
        if folder:
            entry_widget.delete(0, tk.END)
            entry_widget.insert(0, folder)
            self.current_browse_dir = folder
            self.save_settings()
    
    def set_current_path(self, entry_widget):
        """Set to current working directory"""
        entry_widget.delete(0, tk.END)
        entry_widget.insert(0, str(Path.cwd()))
        self.current_browse_dir = str(Path.cwd())
        self.save_settings()
    
    def load_config_from_folder(self, folder_path):
        """Load settings from .TakData/download_config.json in the selected folder"""
        if not folder_path:
            messagebox.showwarning("No Folder", "Please select an output directory first.")
            return
        
        takdata_path = Path(folder_path) / self.tak_data_dir
        config_file = takdata_path / "download_config.json"
        
        if not config_file.exists():
            messagebox.showwarning("Not Found", f"No configuration found in:\n{takdata_path}\n\nRun Download-Playlist first to create it.")
            return
        
        try:
            with open(config_file, 'r') as f:
                config_data = json.load(f)
            
            if "PlaylistUrl" in config_data:
                self.download_url.delete(0, tk.END)
                self.download_url.insert(0, config_data["PlaylistUrl"])
            if "Format" in config_data:
                format_val = config_data["Format"]
                self.download_format.set(format_val)
                self.retry_format.set(format_val)
                self.move_format.set(format_val)
            if "Quality" in config_data:
                quality_val = config_data["Quality"]
                self.download_quality.set(quality_val)
                self.retry_quality.set(quality_val)
                self.move_quality.set(quality_val)
            if "SleepInterval" in config_data:
                sleep_val = str(config_data["SleepInterval"])
                self.download_sleep.delete(0, tk.END)
                self.download_sleep.insert(0, sleep_val)
                self.retry_sleep.delete(0, tk.END)
                self.retry_sleep.insert(0, sleep_val)
            if "EnableArchive" in config_data:
                self.download_archive.set(config_data["EnableArchive"])
            
            self.download_output.delete(0, tk.END)
            self.download_output.insert(0, str(folder_path))
            self.retry_output.delete(0, tk.END)
            self.retry_output.insert(0, str(folder_path))
            self.move_output.delete(0, tk.END)
            self.move_output.insert(0, str(folder_path))
            
            messagebox.showinfo("Success", f"Settings loaded from:\n{config_file}")
            self.save_settings()
            
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load config: {str(e)}")
    
    def save_settings(self):
        """Save current settings to JSON file"""
        settings = {
            "download": {
                "url": self.download_url.get(),
                "output": self.download_output.get(),
                "sleep": self.download_sleep.get(),
                "format": self.download_format.get(),
                "quality": self.download_quality.get(),
                "archive": self.download_archive.get()
            },
            "retry": {
                "output": self.retry_output.get(),
                "sleep": self.retry_sleep.get(),
                "format": self.retry_format.get(),
                "quality": self.retry_quality.get()
            },
            "move": {
                "output": self.move_output.get(),
                "format": self.move_format.get(),
                "quality": self.move_quality.get()
            },
            "scripts_dir": str(self.script_dir),
            "current_browse_dir": self.current_browse_dir,
            "dark_mode": self.dark_mode.get(),
            "last_saved": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
        
        try:
            with open(self.settings_file, "w") as f:
                json.dump(settings, f, indent=2)
            return True
        except Exception as e:
            print(f"Failed to save settings: {e}")
            return False
    
    def save_tasks(self):
        """Save scheduled tasks to JSON file"""
        tasks_data = [task.to_dict() for task in self.tasks.values()]
        try:
            with open(self.tasks_file, "w") as f:
                json.dump(tasks_data, f, indent=2)
            return True
        except Exception as e:
            print(f"Failed to save tasks: {e}")
            return False
    
    def load_tasks(self):
        """Load scheduled tasks from JSON file"""
        if not self.tasks_file.exists():
            return
        
        try:
            with open(self.tasks_file, "r") as f:
                tasks_data = json.load(f)
            
            for data in tasks_data:
                task = ScheduledTask.from_dict(data)
                self.tasks[task.id] = task
            
            self.update_task_list()
        except Exception as e:
            print(f"Failed to load tasks: {e}")
    
    def load_settings(self):
        """Load settings from JSON file"""
        if not self.settings_file.exists():
            return False
        
        try:
            with open(self.settings_file, "r") as f:
                settings = json.load(f)
            
            d = settings.get("download", {})
            self.download_url.insert(0, d.get("url", ""))
            self.download_output.insert(0, d.get("output", ""))
            self.download_sleep.insert(0, d.get("sleep", ""))
            self.download_format.set(d.get("format", "mp3"))
            self.download_quality.set(d.get("quality", "mid"))
            self.download_archive.set(d.get("archive", False))
            
            r = settings.get("retry", {})
            self.retry_output.insert(0, r.get("output", ""))
            self.retry_sleep.insert(0, r.get("sleep", ""))
            self.retry_format.set(r.get("format", "mp3"))
            self.retry_quality.set(r.get("quality", "mid"))
            
            m = settings.get("move", {})
            self.move_output.insert(0, m.get("output", ""))
            self.move_format.set(m.get("format", "mp3"))
            self.move_quality.set(m.get("quality", "mid"))
            
            scripts_dir = settings.get("scripts_dir", "")
            if scripts_dir and Path(scripts_dir).exists():
                self.script_dir = Path(scripts_dir)
                self.scripts_dir_var.set(str(self.script_dir))
            
            self.current_browse_dir = settings.get("current_browse_dir", str(Path.cwd()))
            
            # Load dark mode setting
            dark_mode = settings.get("dark_mode", False)
            self.dark_mode.set(dark_mode)
            if dark_mode:
                self.toggle_dark_mode()
            
            return True
        except Exception as e:
            print(f"Failed to load settings: {e}")
            return False
    
    def on_closing(self):
        """Handle window closing - exit on Linux, minimize to tray on Windows"""
        if self.tray_enabled:
            # On Windows, minimize to tray
            self.minimize_to_tray()
        else:
            # On Linux, exit completely
            self.quit_application()
    
    def stop_current_download(self):
        """Stop the currently running download"""
        if hasattr(self, 'current_process') and self.current_process and self.current_process.poll() is None:
            self.current_process.terminate()
            self.update_status("Process terminated by user.\n")
    
    def update_status(self, message, status_widget=None):
        """Update status text area"""
        if status_widget is None:
            status_widget = self.download_status
        status_widget.insert(tk.END, message)
        status_widget.see(tk.END)
        self.root.update_idletasks()
    
    def build_download_command(self):
        """Build download playlist command"""
        script_path = self.script_dir / f"Download-Playlist{self.script_ext}"
        
        if not script_path.exists():
            messagebox.showerror("Error", f"Script not found: {script_path}")
            return None
        
        cmd = []
        if self.os_type == "Windows":
            cmd = ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", str(script_path)]
        else:
            cmd = ["/bin/bash", str(script_path)]
        
        url = self.download_url.get().strip()
        if not url:
            messagebox.showerror("Error", "Playlist URL is required")
            return None
        
        cmd.extend(["-p", url])
        
        output = self.download_output.get().strip()
        if output:
            cmd.extend(["-o", output])
        
        sleep = self.download_sleep.get().strip()
        if sleep:
            cmd.extend(["-t", sleep])
        
        format_val = self.download_format.get().strip()
        if format_val and format_val != "mp3":
            cmd.extend(["-f", format_val])
        
        quality = self.download_quality.get().strip()
        if quality and quality != "mid":
            cmd.extend(["-q", quality])
        
        if self.download_archive.get():
            cmd.append("-a")
        
        return cmd
    
    def build_retry_command(self):
        """Build retry failed command"""
        script_path = self.script_dir / f"Retry-Failed{self.script_ext}"
        
        if not script_path.exists():
            messagebox.showerror("Error", f"Script not found: {script_path}")
            return None
        
        cmd = []
        if self.os_type == "Windows":
            cmd = ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", str(script_path)]
        else:
            cmd = ["/bin/bash", str(script_path)]
        
        output = self.retry_output.get().strip()
        if output:
            cmd.extend(["-o", output])
        
        sleep = self.retry_sleep.get().strip()
        if sleep:
            cmd.extend(["-t", sleep])
        
        format_val = self.retry_format.get().strip()
        if format_val and format_val != "mp3":
            cmd.extend(["-f", format_val])
        
        quality = self.retry_quality.get().strip()
        if quality and quality != "mid":
            cmd.extend(["-q", quality])
        
        return cmd
    
    def build_move_command(self):
        """Build move recovered command"""
        script_path = self.script_dir / f"Move-Recovered{self.script_ext}"
        
        if not script_path.exists():
            messagebox.showerror("Error", f"Script not found: {script_path}")
            return None
        
        cmd = []
        if self.os_type == "Windows":
            cmd = ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", str(script_path)]
        else:
            cmd = ["/bin/bash", str(script_path)]
        
        output = self.move_output.get().strip()
        if output:
            cmd.extend(["-o", output])
        
        format_val = self.move_format.get().strip()
        if format_val and format_val != "mp3":
            cmd.extend(["-f", format_val])
        
        quality = self.move_quality.get().strip()
        if quality and quality != "mid":
            cmd.extend(["-q", quality])
        
        return cmd
    
    def run_script(self, script_type):
        """Run the selected script in a separate thread"""
        self.save_settings()
        
        if script_type == "download":
            cmd = self.build_download_command()
            status_widget = self.download_status
            progress_bar = self.download_progress
            btn = self.download_btn
        elif script_type == "retry":
            cmd = self.build_retry_command()
            status_widget = self.retry_status
            progress_bar = self.retry_progress
            btn = self.retry_btn
        else:
            cmd = self.build_move_command()
            status_widget = self.move_status
            progress_bar = self.move_progress
            btn = self.move_btn
        
        if not cmd:
            return
        
        btn.config(state=tk.DISABLED)
        progress_bar.start(10)
        status_widget.delete(1.0, tk.END)
        
        self.current_process = None
        thread = threading.Thread(target=self.execute_script, args=(cmd, status_widget, progress_bar, btn))
        thread.daemon = True
        thread.start()
    
    def execute_script(self, cmd, status_widget, progress_bar, btn):
        """Execute the script and capture output"""
        try:
            env = os.environ.copy()
            
            process_flags = {}
            if self.os_type == "Windows":
                process_flags['creationflags'] = subprocess.CREATE_NO_WINDOW
            
            self.current_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True,
                env=env,
                cwd=str(self.script_dir),
                **process_flags
            )
            
            for line in self.current_process.stdout:
                clean_line = strip_ansi_codes(line)
                status_widget.insert(tk.END, clean_line)
                status_widget.see(tk.END)
                self.root.update_idletasks()
            
            return_code = self.current_process.wait()
            
            if return_code == 0:
                status_widget.insert(tk.END, "\n[SUCCESS] Process completed successfully.\n")
            else:
                status_widget.insert(tk.END, f"\n[ERROR] Process exited with code {return_code}\n")
            
        except Exception as e:
            status_widget.insert(tk.END, f"\n[ERROR] {str(e)}\n")
        finally:
            progress_bar.stop()
            btn.config(state=tk.NORMAL)
            self.current_process = None


def main():
    root = tk.Tk()
    app = YouTubeDownloaderGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()