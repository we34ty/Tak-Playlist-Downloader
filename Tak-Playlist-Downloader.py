#!/usr/bin/env python3
"""
Tak Playlist Downloader
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
from datetime import datetime

class TakDownloaderGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Tak Playlist Downloader")
        self.root.geometry("950x700")  # Reduced from 800 to 700
        self.root.minsize(800, 600)    # Set minimum size
        self.root.resizable(True, True)
        
        # Detect OS and set script extension
        self.os_type = platform.system()
        if self.os_type == "Windows":
            self.script_ext = ".ps1"
        else:
            self.script_ext = ".sh"
        
        # Get the correct directory for saving settings
        self.config_dir = self.get_config_dir()
        
        # Settings file path - saved in user's home directory (persists across versions)
        self.settings_file = self.config_dir / "yt_downloader_settings.json"
        
        # Script directory - where the PowerShell/bash scripts are located
        # By default, look in the same directory as the executable
        if getattr(sys, 'frozen', False):
            # Running as PyInstaller executable
            self.script_dir = Path(os.path.dirname(sys.executable))
        else:
            # Running as Python script
            self.script_dir = Path(__file__).parent
        
        # Current browsing directory for file dialogs
        self.current_browse_dir = str(Path.cwd())
        
        # TakData subfolder name
        self.tak_data_dir = ".TakData"
        
        # Set up the UI
        self.setup_ui()
        
        # Load saved settings
        self.load_settings()
    
    def get_config_dir(self):
        """Get the user's config directory for storing settings"""
        if self.os_type == "Windows":
            # Windows: %APPDATA%\YouTubeDownloader
            base_dir = Path(os.environ.get('APPDATA', Path.home() / 'AppData/Roaming'))
        else:
            # Linux/macOS: ~/.config/YouTubeDownloader
            base_dir = Path.home() / '.config'
        
        config_dir = base_dir / 'YouTubeDownloader'
        config_dir.mkdir(parents=True, exist_ok=True)
        return config_dir
    
    def get_takdata_path(self, output_dir):
        """Get the TakData path for a given output directory"""
        takdata_path = Path(output_dir) / self.tak_data_dir
        return takdata_path
    
    def setup_ui(self):
        """Setup the entire user interface"""
        # Create main frame
        main_frame = ttk.Frame(self.root, padding="5")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Create notebooks (tabs)
        self.notebook = ttk.Notebook(main_frame)
        self.notebook.pack(fill=tk.BOTH, expand=True)
        
        # Create tabs
        self.download_tab = ttk.Frame(self.notebook)
        self.retry_tab = ttk.Frame(self.notebook)
        self.move_tab = ttk.Frame(self.notebook)
        self.settings_tab = ttk.Frame(self.notebook)
        
        self.notebook.add(self.download_tab, text="Download Playlist")
        self.notebook.add(self.retry_tab, text="Retry Failed")
        self.notebook.add(self.move_tab, text="Move Recovered")
        self.notebook.add(self.settings_tab, text="Settings")
        
        # Setup each tab
        self.setup_download_tab()
        self.setup_retry_tab()
        self.setup_move_tab()
        self.setup_settings_tab()
        
        # Bind save on window close
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)
    
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
    
    def setup_download_tab(self):
        """Setup the Download Playlist tab"""
        # Use grid layout with weight configuration
        main_frame = ttk.Frame(self.download_tab, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Configure grid weights
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
        
        # Note about TakData folder
        ttk.Label(main_frame, text="Note: All logs and settings are stored in 'TakData' subfolder", foreground="gray").grid(row=2, column=0, columnspan=4, sticky=tk.W, pady=2)
        
        # Separator
        ttk.Separator(main_frame, orient='horizontal').grid(row=3, column=0, columnspan=4, sticky=tk.W+tk.E, pady=5)
        
        # Options frame
        options_frame = ttk.LabelFrame(main_frame, text="Options", padding="8")
        options_frame.grid(row=4, column=0, columnspan=4, sticky=tk.W+tk.E, pady=5)
        
        # Configure options frame grid
        options_frame.columnconfigure(1, weight=0)
        options_frame.columnconfigure(3, weight=1)
        
        # Sleep Interval
        ttk.Label(options_frame, text="Sleep Interval (seconds):").grid(row=0, column=0, sticky=tk.W, pady=3)
        self.download_sleep = ttk.Entry(options_frame, width=10)
        self.download_sleep.grid(row=0, column=1, sticky=tk.W, pady=3)
        self.download_sleep.bind('<KeyRelease>', lambda e: self.save_settings())
        ttk.Label(options_frame, text="(0 = no delay, default: 11)").grid(row=0, column=2, sticky=tk.W, padx=5)
        
        # Format
        ttk.Label(options_frame, text="Format:").grid(row=1, column=0, sticky=tk.W, pady=3)
        self.download_format = ttk.Combobox(options_frame, values=["mp3", "m4a", "opus", "flac", "wav", "mp4", "webm", "mkv"], width=10)
        self.download_format.grid(row=1, column=1, sticky=tk.W, pady=3)
        self.download_format.bind('<<ComboboxSelected>>', lambda e: self.save_settings())
        
        # Quality
        ttk.Label(options_frame, text="Quality:").grid(row=1, column=2, sticky=tk.W, pady=3, padx=10)
        self.download_quality = ttk.Combobox(options_frame, values=["low", "mid", "high"], width=8)
        self.download_quality.grid(row=1, column=3, sticky=tk.W, pady=3)
        self.download_quality.bind('<<ComboboxSelected>>', lambda e: self.save_settings())
        
        # Archive Recovery
        self.download_archive = tk.BooleanVar()
        ttk.Checkbutton(options_frame, text="Enable Archive Recovery (-a)", variable=self.download_archive, command=self.save_settings).grid(row=2, column=0, columnspan=2, sticky=tk.W, pady=3)
        
        # Load config from folder button
        ttk.Button(options_frame, text="Load Settings from Folder", command=lambda: self.load_config_from_folder(self.download_output.get())).grid(row=2, column=2, columnspan=2, sticky=tk.E, pady=3)
        
        # Progress frame
        progress_frame = ttk.LabelFrame(main_frame, text="Progress", padding="8")
        progress_frame.grid(row=5, column=0, columnspan=4, sticky=tk.W+tk.E+tk.N+tk.S, pady=5)
        progress_frame.columnconfigure(0, weight=1)
        progress_frame.rowconfigure(1, weight=1)
        
        self.download_progress = ttk.Progressbar(progress_frame, mode='indeterminate')
        self.download_progress.grid(row=0, column=0, sticky=tk.W+tk.E, pady=3)
        
        self.download_status = scrolledtext.ScrolledText(progress_frame, height=10, width=80)
        self.download_status.grid(row=1, column=0, sticky=tk.W+tk.E+tk.N+tk.S, pady=3)
        
        # Configure main frame to allow progress frame to expand
        main_frame.rowconfigure(5, weight=1)
        
        # Buttons
        button_frame = ttk.Frame(main_frame)
        button_frame.grid(row=6, column=0, columnspan=4, pady=8)
        
        self.download_btn = ttk.Button(button_frame, text="Start Download", command=lambda: self.run_script("download"))
        self.download_btn.pack(side=tk.LEFT, padx=5)
        
        ttk.Button(button_frame, text="Stop", command=self.stop_process).pack(side=tk.LEFT, padx=5)
        ttk.Button(button_frame, text="Clear Output", command=lambda: self.download_status.delete(1.0, tk.END)).pack(side=tk.LEFT, padx=5)
    
    def setup_retry_tab(self):
        """Setup the Retry Failed tab"""
        main_frame = ttk.Frame(self.retry_tab, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Configure grid weights
        main_frame.columnconfigure(1, weight=1)
        
        # Working Directory
        ttk.Label(main_frame, text="Working Directory:").grid(row=0, column=0, sticky=tk.W, pady=3)
        self.retry_output = ttk.Entry(main_frame, width=70)
        self.retry_output.grid(row=0, column=1, sticky=tk.W+tk.E, pady=3)
        self.retry_output.bind('<KeyRelease>', lambda e: self.save_settings())
        ttk.Button(main_frame, text="Browse", command=lambda: self.browse_folder(self.retry_output)).grid(row=0, column=2, padx=3)
        ttk.Button(main_frame, text="Use Current", command=lambda: self.set_current_path(self.retry_output)).grid(row=0, column=3, padx=3)
        
        # Note about TakData folder
        ttk.Label(main_frame, text="Note: All logs and settings are stored in 'TakData' subfolder", foreground="gray").grid(row=1, column=0, columnspan=4, sticky=tk.W, pady=2)
        
        # Separator
        ttk.Separator(main_frame, orient='horizontal').grid(row=2, column=0, columnspan=4, sticky=tk.W+tk.E, pady=5)
        
        # Options frame
        options_frame = ttk.LabelFrame(main_frame, text="Options", padding="8")
        options_frame.grid(row=3, column=0, columnspan=4, sticky=tk.W+tk.E, pady=5)
        options_frame.columnconfigure(1, weight=0)
        options_frame.columnconfigure(3, weight=1)
        
        # Sleep Interval
        ttk.Label(options_frame, text="Sleep Interval (seconds):").grid(row=0, column=0, sticky=tk.W, pady=3)
        self.retry_sleep = ttk.Entry(options_frame, width=10)
        self.retry_sleep.grid(row=0, column=1, sticky=tk.W, pady=3)
        self.retry_sleep.bind('<KeyRelease>', lambda e: self.save_settings())
        ttk.Label(options_frame, text="(default: 11)").grid(row=0, column=2, sticky=tk.W, padx=5)
        
        # Format
        ttk.Label(options_frame, text="Format:").grid(row=1, column=0, sticky=tk.W, pady=3)
        self.retry_format = ttk.Combobox(options_frame, values=["mp3", "m4a", "opus", "flac", "wav", "mp4", "webm", "mkv"], width=10)
        self.retry_format.grid(row=1, column=1, sticky=tk.W, pady=3)
        self.retry_format.bind('<<ComboboxSelected>>', lambda e: self.save_settings())
        
        # Quality
        ttk.Label(options_frame, text="Quality:").grid(row=1, column=2, sticky=tk.W, pady=3, padx=10)
        self.retry_quality = ttk.Combobox(options_frame, values=["low", "mid", "high"], width=8)
        self.retry_quality.grid(row=1, column=3, sticky=tk.W, pady=3)
        self.retry_quality.bind('<<ComboboxSelected>>', lambda e: self.save_settings())
        
        # Load config from folder button
        ttk.Button(options_frame, text="Load Settings from Folder", command=lambda: self.load_config_from_folder(self.retry_output.get())).grid(row=2, column=2, columnspan=2, sticky=tk.E, pady=3)
        
        # Progress frame
        progress_frame = ttk.LabelFrame(main_frame, text="Progress", padding="8")
        progress_frame.grid(row=4, column=0, columnspan=4, sticky=tk.W+tk.E+tk.N+tk.S, pady=5)
        progress_frame.columnconfigure(0, weight=1)
        progress_frame.rowconfigure(1, weight=1)
        
        self.retry_progress = ttk.Progressbar(progress_frame, mode='indeterminate')
        self.retry_progress.grid(row=0, column=0, sticky=tk.W+tk.E, pady=3)
        
        self.retry_status = scrolledtext.ScrolledText(progress_frame, height=10, width=80)
        self.retry_status.grid(row=1, column=0, sticky=tk.W+tk.E+tk.N+tk.S, pady=3)
        
        main_frame.rowconfigure(4, weight=1)
        
        # Buttons
        button_frame = ttk.Frame(main_frame)
        button_frame.grid(row=5, column=0, columnspan=4, pady=8)
        
        self.retry_btn = ttk.Button(button_frame, text="Start Retry", command=lambda: self.run_script("retry"))
        self.retry_btn.pack(side=tk.LEFT, padx=5)
        
        ttk.Button(button_frame, text="Stop", command=self.stop_process).pack(side=tk.LEFT, padx=5)
        ttk.Button(button_frame, text="Clear Output", command=lambda: self.retry_status.delete(1.0, tk.END)).pack(side=tk.LEFT, padx=5)
    
    def setup_move_tab(self):
        """Setup the Move Recovered tab"""
        main_frame = ttk.Frame(self.move_tab, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Configure grid weights
        main_frame.columnconfigure(1, weight=1)
        
        # Working Directory
        ttk.Label(main_frame, text="Working Directory:").grid(row=0, column=0, sticky=tk.W, pady=3)
        self.move_output = ttk.Entry(main_frame, width=70)
        self.move_output.grid(row=0, column=1, sticky=tk.W+tk.E, pady=3)
        self.move_output.bind('<KeyRelease>', lambda e: self.save_settings())
        ttk.Button(main_frame, text="Browse", command=lambda: self.browse_folder(self.move_output)).grid(row=0, column=2, padx=3)
        ttk.Button(main_frame, text="Use Current", command=lambda: self.set_current_path(self.move_output)).grid(row=0, column=3, padx=3)
        
        # Note about TakData folder
        ttk.Label(main_frame, text="Note: All logs and settings are stored in 'TakData' subfolder", foreground="gray").grid(row=1, column=0, columnspan=4, sticky=tk.W, pady=2)
        
        # Separator
        ttk.Separator(main_frame, orient='horizontal').grid(row=2, column=0, columnspan=4, sticky=tk.W+tk.E, pady=5)
        
        # Options frame
        options_frame = ttk.LabelFrame(main_frame, text="Options", padding="8")
        options_frame.grid(row=3, column=0, columnspan=4, sticky=tk.W+tk.E, pady=5)
        options_frame.columnconfigure(1, weight=0)
        options_frame.columnconfigure(3, weight=1)
        
        # Format
        ttk.Label(options_frame, text="Target Format:").grid(row=0, column=0, sticky=tk.W, pady=3)
        self.move_format = ttk.Combobox(options_frame, values=["mp3", "m4a", "opus", "flac", "wav", "mp4", "webm", "mkv"], width=10)
        self.move_format.grid(row=0, column=1, sticky=tk.W, pady=3)
        self.move_format.bind('<<ComboboxSelected>>', lambda e: self.save_settings())
        
        # Quality
        ttk.Label(options_frame, text="Quality:").grid(row=0, column=2, sticky=tk.W, pady=3, padx=10)
        self.move_quality = ttk.Combobox(options_frame, values=["low", "mid", "high"], width=8)
        self.move_quality.grid(row=0, column=3, sticky=tk.W, pady=3)
        self.move_quality.bind('<<ComboboxSelected>>', lambda e: self.save_settings())
        
        # Load config from folder button
        ttk.Button(options_frame, text="Load Settings from Folder", command=lambda: self.load_config_from_folder(self.move_output.get())).grid(row=1, column=2, columnspan=2, sticky=tk.E, pady=3)
        
        # Progress frame
        progress_frame = ttk.LabelFrame(main_frame, text="Progress", padding="8")
        progress_frame.grid(row=4, column=0, columnspan=4, sticky=tk.W+tk.E+tk.N+tk.S, pady=5)
        progress_frame.columnconfigure(0, weight=1)
        progress_frame.rowconfigure(1, weight=1)
        
        self.move_progress = ttk.Progressbar(progress_frame, mode='indeterminate')
        self.move_progress.grid(row=0, column=0, sticky=tk.W+tk.E, pady=3)
        
        self.move_status = scrolledtext.ScrolledText(progress_frame, height=10, width=80)
        self.move_status.grid(row=1, column=0, sticky=tk.W+tk.E+tk.N+tk.S, pady=3)
        
        main_frame.rowconfigure(4, weight=1)
        
        # Buttons
        button_frame = ttk.Frame(main_frame)
        button_frame.grid(row=5, column=0, columnspan=4, pady=8)
        
        self.move_btn = ttk.Button(button_frame, text="Start Move/Convert", command=lambda: self.run_script("move"))
        self.move_btn.pack(side=tk.LEFT, padx=5)
        
        ttk.Button(button_frame, text="Stop", command=self.stop_process).pack(side=tk.LEFT, padx=5)
        ttk.Button(button_frame, text="Clear Output", command=lambda: self.move_status.delete(1.0, tk.END)).pack(side=tk.LEFT, padx=5)
    
    def setup_settings_tab(self):
        """Setup the Settings tab"""
        main_frame = ttk.Frame(self.settings_tab, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Configure grid
        main_frame.columnconfigure(1, weight=1)
        
        # Scripts directory
        ttk.Label(main_frame, text="Scripts Directory:").grid(row=0, column=0, sticky=tk.W, pady=5)
        self.scripts_dir_var = tk.StringVar(value=str(self.script_dir))
        scripts_entry = ttk.Entry(main_frame, textvariable=self.scripts_dir_var, width=70)
        scripts_entry.grid(row=0, column=1, sticky=tk.W+tk.E, pady=5)
        scripts_entry.bind('<KeyRelease>', lambda e: self.save_settings())
        ttk.Button(main_frame, text="Browse", command=self.browse_scripts_dir).grid(row=0, column=2, padx=5)
        
        # Separator
        ttk.Separator(main_frame, orient='horizontal').grid(row=1, column=0, columnspan=3, sticky=tk.W+tk.E, pady=10)
        
        # Config location info
        info_frame = ttk.LabelFrame(main_frame, text="Configuration", padding="10")
        info_frame.grid(row=2, column=0, columnspan=3, sticky=tk.W+tk.E, pady=5)
        
        ttk.Label(info_frame, text=f"Settings saved to: {self.settings_file}").pack(anchor=tk.W, pady=2)
        ttk.Label(info_frame, text="Settings are automatically saved when you change any field").pack(anchor=tk.W, pady=2)
        ttk.Label(info_frame, text="No manual save needed - everything is auto-saved").pack(anchor=tk.W, pady=2)
        ttk.Label(info_frame, text="Logs and script data are stored in 'TakData' subfolder in the output directory").pack(anchor=tk.W, pady=2)
        
        # System info (make scrollable if too tall)
        sys_frame = ttk.LabelFrame(main_frame, text="System Information", padding="10")
        sys_frame.grid(row=3, column=0, columnspan=3, sticky=tk.W+tk.E, pady=5)
        
        ttk.Label(sys_frame, text=f"Operating System: {self.os_type}").pack(anchor=tk.W, pady=2)
        ttk.Label(sys_frame, text=f"Script Extension: {self.script_ext}").pack(anchor=tk.W, pady=2)
        ttk.Label(sys_frame, text=f"Python Version: {sys.version.split()[0]}").pack(anchor=tk.W, pady=2)
        ttk.Label(sys_frame, text=f"Executable Location: {self.script_dir}").pack(anchor=tk.W, pady=2)
        
        # About
        about_frame = ttk.LabelFrame(main_frame, text="About", padding="10")
        about_frame.grid(row=4, column=0, columnspan=3, sticky=tk.W+tk.E, pady=5)
        
        about_text = """Tak Playlist Downloader GUI
A cross-platform graphical interface for downloading YouTube playlists.

Features:
- Download entire playlists as MP3/MP4
- Archive recovery for deleted videos
- Retry failed downloads
- Convert recovered files
- Settings automatically saved
- All logs stored in 'TakData' subfolder

Scripts required in the same directory as this executable:
- Download-Playlist.ps1/.sh
- Retry-Failed.ps1/.sh
- Move-Recovered.ps1/.sh"""
        
        about_label = ttk.Label(about_frame, text=about_text, justify=tk.LEFT)
        about_label.pack(anchor=tk.W, pady=5)
        
        # Make settings tab scrollable if content overflows
        canvas = tk.Canvas(main_frame)
        scrollbar = ttk.Scrollbar(main_frame, orient="vertical", command=canvas.yview)
        scrollable_frame = ttk.Frame(canvas)
        
        scrollable_frame.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        
        # This is a simpler approach - just pack everything normally
        # The settings tab is typically not too tall
    
    def browse_scripts_dir(self):
        """Browse for scripts directory"""
        folder = filedialog.askdirectory(initialdir=self.current_browse_dir)
        if folder:
            self.scripts_dir_var.set(folder)
            self.script_dir = Path(folder)
            self.current_browse_dir = folder
            self.save_settings()
    
    def load_config_from_folder(self, folder_path):
        """Load settings from TakData/download_config.json in the selected folder"""
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
            
            # Update download tab fields
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
            
            # Update output directory fields
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
        """Save current settings to JSON file (auto-called on any change)"""
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
            "last_saved": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
        
        try:
            with open(self.settings_file, "w") as f:
                json.dump(settings, f, indent=2)
            return True
        except Exception as e:
            print(f"Failed to save settings: {e}")
            return False
    
    def load_settings(self):
        """Load settings from JSON file"""
        if not self.settings_file.exists():
            return False
        
        try:
            with open(self.settings_file, "r") as f:
                settings = json.load(f)
            
            # Load download settings
            d = settings.get("download", {})
            self.download_url.insert(0, d.get("url", ""))
            self.download_output.insert(0, d.get("output", ""))
            self.download_sleep.insert(0, d.get("sleep", ""))
            self.download_format.set(d.get("format", "mp3"))
            self.download_quality.set(d.get("quality", "mid"))
            self.download_archive.set(d.get("archive", False))
            
            # Load retry settings
            r = settings.get("retry", {})
            self.retry_output.insert(0, r.get("output", ""))
            self.retry_sleep.insert(0, r.get("sleep", ""))
            self.retry_format.set(r.get("format", "mp3"))
            self.retry_quality.set(r.get("quality", "mid"))
            
            # Load move settings
            m = settings.get("move", {})
            self.move_output.insert(0, m.get("output", ""))
            self.move_format.set(m.get("format", "mp3"))
            self.move_quality.set(m.get("quality", "mid"))
            
            # Load scripts directory
            scripts_dir = settings.get("scripts_dir", "")
            if scripts_dir and Path(scripts_dir).exists():
                self.script_dir = Path(scripts_dir)
                self.scripts_dir_var.set(str(self.script_dir))
            
            # Load current browse directory
            self.current_browse_dir = settings.get("current_browse_dir", str(Path.cwd()))
            
            return True
        except Exception as e:
            print(f"Failed to load settings: {e}")
            return False
    
    def on_closing(self):
        """Handle window closing - save settings then close"""
        self.save_settings()
        self.root.destroy()
    
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
                status_widget.insert(tk.END, line)
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
    
    def stop_process(self):
        """Stop the currently running process"""
        if self.current_process and self.current_process.poll() is None:
            self.current_process.terminate()
            tab_id = self.notebook.index(self.notebook.select())
            if tab_id == 0:
                self.download_status.insert(tk.END, "\n[STOPPED] Process terminated by user.\n")
            elif tab_id == 1:
                self.retry_status.insert(tk.END, "\n[STOPPED] Process terminated by user.\n")
            elif tab_id == 2:
                self.move_status.insert(tk.END, "\n[STOPPED] Process terminated by user.\n")


def main():
    root = tk.Tk()
    app = TakDownloaderGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()