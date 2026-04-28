# Tak Playlist Downloader

A complete solution for downloading YouTube playlists as MP3/MP4 files with automatic retry and archive recovery capabilities.

## 🚀 Quick Start (Windows .exe)

### 1. Download and Extract
- Download `TakPlaylistDownloader.exe` from the releases page
- Create a folder (e.g., `C:\TakDownloader`) and place the .exe there
- **No installation required** - just double-click to run

### 2. First Run - What You Need
The program will automatically download `yt-dlp.exe` and `ffmpeg.exe` to the same folder on first use. These are required for downloading and converting.

### 3. Download Your First Playlist

**Step 1:** Get a YouTube playlist URL
- Go to YouTube, open any playlist
- Copy the URL from your browser's address bar
- Example: `https://youtube.com/playlist?list=PLqM1J9soKXtisS_woMHvCvmHGgG7ADtlF`

**Step 2:** Paste URL in the "Playlist URL" field

**Step 3:** Choose output folder (or click "Use Current")

**Step 4:** Click "Start Download"

That's it! Your songs will download as MP3 files (default).

### 4. Basic Settings

| Setting | What It Does | Recommended |
|---------|--------------|-------------|
| **Sleep Interval** | Seconds between downloads (avoid rate limiting) | 11 seconds |
| **Format** | mp3, mp4, flac, etc. | mp3 |
| **Quality** | low, mid, high | mid |
| **Archive Recovery (-a)** | Finds deleted videos from Internet Archive | Enable if desired |

## 📁 Folder Structure After Download

Your Music Folder/
├── .TakData/ ← All program data (hidden folder)
│   ├── downloaded_ids.txt ← Successfully downloaded
│   ├── failed_ids.txt ← Failed (can retry)
│   ├── permanently_failed_ids.txt ← Truly unavailable
│   ├── download_config.json ← Your saved settings
│   └── archive_recovered/ ← Recovered files (temporary)
│
├── Artist Name - Song Title.mp3 ← Your downloaded songs
├── Another Artist - Another Song.mp3
└── ...

> **Note:** The `.TakData` folder is hidden on Linux/macOS. On Windows, you may need to enable "Show hidden files" in File Explorer.

## 🎮 Complete Workflow Example

### Simple Download
1. Open the program
2. Paste playlist URL
3. Click "Start Download"
4. Wait for completion (progress shown in the window)

### Download with Archive Recovery (for deleted videos)
1. Check "Enable Archive Recovery (-a)"
2. Click "Start Download"
3. If a video is deleted from YouTube, the program automatically searches:
   - GhostArchive
   - Archive.org
   - Wayback Machine
   - Hobune.stream

### Retry Failed Downloads
1. Go to the "Retry Failed" tab
2. Select the output directory (where your `.TakData` folder is)
3. Click "Start Retry"

### Move Recovered Files
1. Go to the "Move Recovered" tab
2. Select the output directory
3. Click "Start Move/Convert"
4. Files are converted to your chosen format

## 🐧 Linux Users

### Option 1: Run the Python Script Directly (Recommended)

```bash
# Install required packages
sudo apt install python3-tk python3-pip
pip install --user pyinstaller  # optional, for building executable

# Download the scripts and run
python3 yt_downloader_gui.py
```

### Option 2: Use the Bash Scripts Directly

```bash
# Make scripts executable
chmod +x Download-Playlist.sh Retry-Failed.sh Move-Recovered.sh

# Download a playlist
./Download-Playlist.sh -p "PLAYLIST_URL" -o "Music" -a

# Retry failed downloads
./Retry-Failed.sh -o "Music"

# Move recovered files
./Move-Recovered.sh -o "Music"
```

### Option 3: Build Linux Executable

```bash
# Install tkinter and pyinstaller
sudo apt install python3-tk
pip install --user pyinstaller

# Build the executable
pyinstaller --onefile --windowed --name "TakPlaylistDownloader" yt_downloader_gui.py

# Run it
./dist/TakPlaylistDownloader
```

## ⚙️ All Command-Line Options (for advanced users)

The program runs the following scripts in the background. You can also run them directly from command line:

### Download-Playlist (Main Downloader)

#### Windows PowerShell
```powershell
.\Download-Playlist.ps1 -p "PLAYLIST_URL" -o "OUTPUT_DIR" -t 11 -f mp3 -q mid -a
```

#### Linux/macOS Bash
```bash
./Download-Playlist.sh -p "PLAYLIST_URL" -o "OUTPUT_DIR" -t 11 -f mp3 -q mid -a
```

| Option | Description | Default |
|--------|-------------|---------|
| -p URL | YouTube playlist URL | Required |
| -o DIR | Output directory | Current directory |
| -t SEC | Sleep between downloads | 11 seconds |
| -f FORMAT | Output format (mp3, mp4, flac, etc.) | mp3 |
| -q QUALITY | Quality: low, mid, high | mid |
| -a | Enable archive recovery | Off |

### Retry-Failed

# Retry videos that failed
```powershell
.\Retry-Failed.ps1 -o "OUTPUT_DIR" -t 5
```

# With different format
```powershell
.\Retry-Failed.ps1 -o "OUTPUT_DIR" -f mp4 -q high
```

### Move-Recovered

# Convert recovered files
```powershell
.\Move-Recovered.ps1 -o "OUTPUT_DIR" -f mp3 -q mid
```

## 🔧 Troubleshooting

**"No .download_config.json found"**

	Run Download-Playlist first with the -p parameter to create settings
	Or use the GUI's "Load Settings from Folder" button after first run

**Weird color codes in output (Windows GUI)**

	Fixed in latest version - ANSI color codes are automatically stripped
	Output now appears as clean text

**"ERROR: Cannot access directory"**

	Make sure the directory path uses backslashes (\) on Windows
	The GUI handles this automatically

**Downloads are very slow**

	Increase sleep interval (YouTube may throttle fast downloads)
	Use lower quality (-q low) for faster downloads

**Videos marked as permanently failed**

	These videos were not found on YouTube or any archive
	Check permanently_failed_ids.txt in the .TakData folder
	To retry anyway, remove the ID from that file

**"jq is required" on Linux**

```bash
sudo apt install jq        # Debian/Ubuntu
sudo dnf install jq        # Fedora
brew install jq            # macOS
```

**"ModuleNotFoundError: No module named 'tkinter'" on Linux**

```bash
sudo apt install python3-tk
```

**"error: externally-managed-environment" on Linux**

```bash
# Use pipx instead
sudo apt install pipx
pipx install pyinstaller

# Or use --user flag
pip install --user pyinstaller
```

## 💡 Tips

	First download - Start with a small playlist to test settings
	Large playlists - Use 10-15 second delay to avoid IP bans
	Archive recovery - Takes longer but can recover deleted videos
	Resume capability - Interrupt with Ctrl+C, progress is saved
	Settings persistence - GUI settings saved to %APPDATA%\TakDownloader\ (Windows) or ~/.config/TakDownloader/ (Linux)

## 📋 Requirements

### Windows (Self-contained)

	Windows 10 or 11
	No Python required - the .exe includes everything

### Linux (Running Python Script)

	Python 3.6+
	tkinter (sudo apt install python3-tk)
	yt-dlp, ffmpeg, curl, jq (auto-installed by scripts)
	Deno (for archive recovery, auto-installed)

## 📝 Notes

	All data files are stored in the .TakData subfolder (hidden) - never in your music folder
	Delete .TakData to completely reset all download progress
	Settings are automatically saved when you change any field
	The GUI saves settings to your user profile, not the program folder
	Downloaded files keep original filenames: Artist - Song Title.mp3
	ANSI color codes are automatically stripped from GUI output for clean display

## ❓ Common Questions

**Q: Can I move the .exe to another folder?**
A: Yes, but you need to copy the .ps1 scripts and the .TakData folder with it.

**Q: Where are my downloaded songs?**
A: In the output directory you specified. The .TakData folder is separate.

**Q: How do I start over?**
A: Delete the .TakData folder in your output directory.

**Q: Can I pause and resume?**
A: Yes, press Ctrl+C to stop. Run the same command again to resume.

**Q: Why do I see a console window when downloading?**
A: That's the PowerShell/Bash script running. It closes automatically when done.

**Q: The program won't start?**
A: Make sure all .ps1 files are in the same folder as the .exe.

**Q: What's the .TakData folder?**
A: It stores all program data (logs, settings, temporary files). It's hidden to keep your music folder clean.

**Q: How do I see hidden folders on Windows?**
A: In File Explorer, click "View" → check "Hidden items".

---

Disclaimer: This tool is for personal use only. Downloading copyrighted content may violate YouTube's Terms of Service.
