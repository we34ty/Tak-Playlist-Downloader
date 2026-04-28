# Tak Playlist Downloader

A complete solution for downloading YouTube playlists as MP3/MP4 files with automatic retry and archive recovery capabilities.

## 🚀 Quick Start

### Windows Users
1. Download `Tak-Playlist-Downloader.exe`
2. Create a folder (e.g., `C:\TakDownloader`) and place the .exe there
3. **Make sure the `.ps1` script files are in the same folder** (see note below)
4. **Double-click to run** - no installation required

### Linux Users
1. Download `Tak-Playlist-Downloader` (Linux executable)
2. Download the `.sh` script files to the same folder
3. Make it executable: `chmod +x Tak-Playlist-Downloader`
4. Run it: `./Tak-Playlist-Downloader`

### Python Users (Alternative)
```bash
python3 Tak-Playlist-Downloader.py
```

⚠️ **Important: Script Files Required**

The executable requires the following script files to be in the SAME folder:

| Platform | Required Files |
|----------|-----------------------------------------------|
| Windows  | Download-Playlist.ps1, Retry-Failed.ps1, Move-Recovered.ps1 |
| Linux    | Download-Playlist.sh, Retry-Failed.sh, Move-Recovered.sh     |

These scripts are included in the download package. Do not move them to a different folder - they must stay next to the executable.

#### Folder Structure (Windows Example)

```
C:\TakDownloader\
├── Tak-Playlist-Downloader.exe    ← The executable
├── Download-Playlist.ps1          ← Required script
├── Retry-Failed.ps1               ← Required script
├── Move-Recovered.ps1             ← Required script
└── .TakData\                      ← Created automatically
```

#### Folder Structure (Linux Example)

```
/home/user/TakDownloader\
├── Tak-Playlist-Downloader        ← The executable
├── Download-Playlist.sh           ← Required script
├── Retry-Failed.sh                ← Required script
├── Move-Recovered.sh              ← Required script
└── .TakData\                      ← Created automatically
```

## 📦 What You Need

The program will automatically download required tools on first use:

- **yt-dlp** - For downloading videos
- **ffmpeg** - For audio/video conversion
	- `ffmpeg.exe` (Windows) or `ffmpeg` (Linux)

These tools will be saved in the same folder as the executable.

## 🎯 Download Your First Playlist

1. Get a YouTube playlist URL
	- Copy from your browser: `https://youtube.com/playlist?list=...`
2. Paste URL in the "Playlist URL" field
3. Choose output folder (or click "Use Current")
4. Click "Start Download"

That's it! Your songs will download as MP3 files (default).

## ⚙️ Basic Settings

| Setting           | What It Does                                 | Recommended |
|-------------------|----------------------------------------------|-------------|
| Sleep Interval    | Seconds between downloads (avoid rate limiting) | 11 seconds  |
| Format            | mp3, mp4, flac, etc.                         | mp3         |
| Quality           | low, mid, high                               | mid         |
| Archive Recovery (-a) | Finds deleted videos from Internet Archive | Enable if desired |

## 📁 Folder Structure

```
Your Music Folder/
├── .TakData/                          ← All program data (hidden folder)
│   ├── downloaded_ids.txt             ← Successfully downloaded
│   ├── failed_ids.txt                 ← Failed (can retry)
│   ├── permanently_failed_ids.txt     ← Truly unavailable
│   ├── download_config.json           ← Your saved settings
│   └── archive_recovered/             ← Recovered files (temporary)
│
├── Artist Name - Song Title.mp3       ← Your downloaded songs
└── ...
```

> **Note:** The .TakData folder is hidden. On Windows, enable "Show hidden items" in File Explorer. On Linux, use `ls -la` to see it.

## 🎮 Complete Workflow

1. **Download a Playlist**
	- Open the program
	- Paste playlist URL
	- Click "Start Download"
2. **Enable Archive Recovery (for deleted videos)**
	- Check "Enable Archive Recovery (-a)"
	- Click "Start Download"
	- Searches: GhostArchive → Archive.org → Wayback Machine → Hobune.stream
3. **Retry Failed Downloads**
	- Go to "Retry Failed" tab
	- Select output directory
	- Click "Start Retry"
4. **Move Recovered Files**
	- Go to "Move Recovered" tab
	- Select output directory
	- Click "Start Move/Convert"

## 🐧 Linux-Specific Instructions

If you see `ModuleNotFoundError: No module named 'tkinter'`

```bash
sudo apt install python3-tk
```

If you see `error: externally-managed-environment`

```bash
# Use pipx instead of pip
sudo apt install pipx
pipx install pyinstaller    # only needed if building
```

If you see `jq is required`

```bash
sudo apt install jq
```

If the executable won't run

```bash
# Make sure it's executable
chmod +x Tak-Playlist-Downloader

# Check that script files are in the same folder
ls -la Download-Playlist.sh Retry-Failed.sh Move-Recovered.sh
```

## 🔧 Troubleshooting

**"Script not found" error**

- Make sure the .ps1 (Windows) or .sh (Linux) files are in the same folder as the executable
- Do not move the scripts to a different location

**"No configuration found"**

- Run a download first to create settings, or
- Use "Load Settings from Folder" button after first run

**Weird color codes in output (\u001b[0;34m)**

- Fixed in latest version - ANSI codes are automatically stripped
- Output now appears as clean text

**"ERROR: Cannot access directory" (Windows)**

- Ensure path uses backslashes (\) - the GUI handles this automatically

**Downloads are very slow**

- Increase sleep interval
- Use lower quality (-q low)

**Videos marked as permanently failed**

- Not found on YouTube or any archive
- Check .TakData/permanently_failed_ids.txt
- Remove ID from that file to retry

## 💡 Tips

- First run - Test with a small playlist first
- Large playlists (1000+ songs) - Use 10-15 second delay
- Archive recovery - Slower but can recover deleted videos
- Resume capability - Press Ctrl+C to stop; run again to resume
- Keep scripts together - Never move the script files away from the executable
- Settings persistence - GUI settings saved to:
	- Windows: %APPDATA%\TakDownloader\
	- Linux: ~/.config/TakDownloader/

## 📋 Requirements

**Windows**

- Windows 10 or 11
- No Python required - the .exe is self-contained
- Script files (.ps1) in same folder as executable

**Linux**

- Python 3.6+ (for GUI) OR use the provided Linux executable
- tkinter: `sudo apt install python3-tk`
- yt-dlp, ffmpeg, curl, jq (auto-installed by scripts)
- Script files (.sh) in same folder as executable

## 📝 Scripts Included

The following scripts are used by the GUI and must remain in the same folder as the executable:

| Platform | Scripts |
|----------|-----------------------------------------------|
| Windows  | Download-Playlist.ps1, Retry-Failed.ps1, Move-Recovered.ps1 |
| Linux    | Download-Playlist.sh, Retry-Failed.sh, Move-Recovered.sh     |

These can also be run directly from command line:

### Windows PowerShell
```powershell
.\Download-Playlist.ps1 -p "URL" -o "Music" -t 11 -f mp3 -q mid -a
```

### Linux Bash
```bash
./Download-Playlist.sh -p "URL" -o "Music" -t 11 -f mp3 -q mid -a
```

| Option   | Description                  | Default         |
|----------|------------------------------|-----------------|
| -p URL   | YouTube playlist URL         | Required        |
| -o DIR   | Output directory             | Current directory |
| -t SEC   | Sleep between downloads      | 11              |
| -f FORMAT| mp3, mp4, flac, etc.         | mp3             |
| -q QUALITY| low, mid, high              | mid             |
| -a       | Enable archive recovery      | Off             |

## ❓ Common Questions

**Q: Can I move the executable to another folder?**
A: Yes, but you must move ALL files together (the .exe, the script files, and the .TakData folder).

**Q: Why do I get "Script not found" error?**
A: The script files (.ps1 or .sh) are missing or in the wrong folder. They must be in the same folder as the executable.

**Q: Where are my downloaded songs?**
A: In the output directory you chose. The .TakData folder is separate.

**Q: How do I start over?**
A: Delete the .TakData folder in your output directory.

**Q: Can I pause and resume?**
A: Yes - press Ctrl+C to stop, run the same command again to resume.

**Q: Why does a console window appear?**
A: That's the script running. It closes automatically when done.

**Q: What's the .TakData folder?**
A: Stores all logs, settings, and temporary files. It's hidden to keep your music folder clean.

**Q: How do I see hidden folders?**
A: Windows: File Explorer → View → "Hidden items". Linux: ls -la

**Q: The Linux executable won't run?**
A: Run chmod +x Tak-Playlist-Downloader first to make it executable.

**Q: Can I run the scripts without the GUI?**
A: Yes, directly from command line using the commands shown above.

---

**Disclaimer:** This tool is for personal use only. Downloading copyrighted content may violate YouTube's Terms of Service.
