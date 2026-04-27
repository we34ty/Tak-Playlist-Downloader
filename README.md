# YouTube Playlist Downloader Suite

A comprehensive suite of scripts for downloading YouTube playlists with advanced features including permanent failure tracking, internet disconnection handling, quality selection, and automatic resume capabilities.

## Features

- **Smart Downloading** – Downloads entire playlists with customizable formats (MP3, MP4, FLAC, etc.)
- **Quality Selection** – Choose between low, mid, or high quality for both audio and video downloads
- **Hidden File Organization** – All log files and archive folders use dot prefix (`.`) to stay hidden and organized
- **Permanent Failure Tracking** – Videos that fail on YouTube are marked permanently failed and never retried
- **Internet Disconnection Handling** – Automatically pauses downloads when internet drops and resumes when connection returns
- **Resume Capability** – Interrupt and restart without re-downloading completed files
- **Hyphen ID Support** – Properly handles video IDs that start with hyphens (e.g., `-_H5A1Xskjg`)
- **Cross-Platform** – Bash scripts for Linux/macOS (full features), PowerShell scripts for Windows (basic features)

---

## File Organization

All scripts use hidden files (starting with `.`) to keep your directory clean:

| File Type                | Name                        | Purpose                                         |
|--------------------------|-----------------------------|-------------------------------------------------|
| Downloaded log           | `.downloaded_ids.txt`       | Tracks successfully downloaded video IDs         |
| Failed log               | `.failed_ids.txt`           | Videos that failed (pending retry)               |
| Recovered log            | `.recovered_ids.txt`        | Videos recovered from archives (Linux only)      |
| Permanently failed log   | `.permanently_failed_ids.txt` | Videos that failed permanently (never retry)   |
| Playlist IDs             | `.playlist_videos.txt`      | All video IDs from the playlist                  |
| Archive directory        | `.archive_recovered/`       | Temporary storage for recovered files (Linux only)|

These hidden files won’t clutter your music directory when using `ls`. Use `ls -la` to see them.

---

## Prerequisites

### Linux/macOS (Bash scripts)

```bash
# Install yt-dlp (standalone binary recommended)
sudo wget https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -O /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp

# Install ffmpeg
sudo apt install ffmpeg        # Debian/Ubuntu
sudo dnf install ffmpeg        # Fedora
brew install ffmpeg            # macOS

# Install curl (for archive recovery)
sudo apt install curl

# Install Deno (required for archive recovery on Linux)
curl -fsSL https://deno.land/install.sh | sh
echo 'export PATH="$HOME/.deno/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Windows (PowerShell scripts)

```powershell
# Install yt-dlp using winget
winget install yt-dlp.yt-dlp

# Install ffmpeg
winget install ffmpeg

# Or download manually and add to PATH:
# - yt-dlp.exe: https://github.com/yt-dlp/yt-dlp/releases
# - ffmpeg.exe: https://www.gyan.dev/ffmpeg/builds/

# Set execution policy (run as Administrator)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Scripts Overview

### 1. Download-Playlist.sh (Linux/macOS) / Download-Playlist.ps1 (Windows)

**Purpose:** Main downloader. Downloads all videos from a YouTube playlist with format selection, quality options, and configurable delay.

**Key Features:**
- Extracts all video IDs from playlist
- Quality selection (low/mid/high) for audio bitrate or video resolution
- Tracks downloaded and permanently failed videos
- Auto-pauses on internet disconnection
- Marks videos as permanently failed if unavailable on YouTube
- Uses hidden log files (.downloaded_ids.txt, etc.)
- Properly handles video IDs starting with hyphens

**Usage (Linux/macOS):**
```bash
./Download-Playlist.sh -p PLAYLIST_URL [OPTIONS]
```
**Usage (Windows PowerShell):**
```powershell
.\Download-Playlist.ps1 -p PLAYLIST_URL [OPTIONS]
```

| Option | Description | Default |
|--------|-------------|---------|
| -p URL | YouTube playlist URL (required) | – |
| -o DIR | Output directory | Current directory |
| -t SECONDS | Sleep between downloads | 11 |
| -f FORMAT | Output format (mp3, mp4, flac, etc.) | mp3 |
| -q QUALITY | Quality: low, mid, high | mid |
| -a | Enable archive recovery (Linux only) | Disabled |
| -h | Show help | – |

**Quality Settings:**

| Quality | Audio (MP3/Opus/etc.) | Video (MP4/WebM/etc.) |
|---------|-----------------------|-----------------------|
| low     | ~80kbps               | Worst available       |
| mid     | ~192kbps              | Up to 480p            |
| high    | ~320kbps              | Best available        |

**Examples:**

Linux/macOS:
```bash
# Basic download as MP3 (mid quality)
./Download-Playlist.sh -p "https://youtube.com/playlist?list=ABC123"

# Download high quality audio with archive recovery
./Download-Playlist.sh -p "URL" -o "$HOME/Music" -q high -a

# Download low quality video to save space
./Download-Playlist.sh -p "URL" -f mp4 -q low -t 5
```

Windows PowerShell:
```powershell
# Basic download as MP3
.\Download-Playlist.ps1 -p "https://youtube.com/playlist?list=ABC123"

# Download to specific folder with custom delay
.\Download-Playlist.ps1 -p "URL" -o "C:\Music" -t 5 -q high
```

---

### 2. Retry-Failed.sh (Linux/macOS) / Retry-Failed.ps1 (Windows)

**Purpose:** Retries videos that failed during main download. Marks still-unavailable videos as permanently failed.

**Key Features:**
- Retries failed videos from .failed_ids.txt
- Marks permanently failed videos to skip future retries
- Handles internet disconnection gracefully
- Uses hidden log files

**Usage (Linux/macOS):**
```bash
./Retry-Failed.sh [OPTIONS]
```
**Usage (Windows PowerShell):**
```powershell
.\Retry-Failed.ps1 [OPTIONS]
```

| Option | Description | Default |
|--------|-------------|---------|
| -o DIR | Output directory | Current directory |
| -t SECONDS | Sleep between retries | 11 |
| -f FORMAT | Output format | mp3 |
| -q QUALITY | Quality: low, mid, high | mid |
| -h | Show help | – |

**Examples:**

Linux/macOS:
```bash
# Retry failed in current directory
./Retry-Failed.sh

# Retry in specific folder with high quality
./Retry-Failed.sh -o "$HOME/Music" -q high -t 5
```

Windows PowerShell:
```powershell
# Retry failed downloads
.\Retry-Failed.ps1 -o "C:\Music" -t 3
```

---

### 3. Move-Recovered.sh (Linux/macOS only)

**Purpose:** Processes files in .archive_recovered folder, converts them to the target format.

**Note:** This script is only available on Linux/macOS as archive recovery is not supported on Windows.

**Usage:**
```bash
./Move-Recovered.sh [OPTIONS]
```

| Option | Description | Default |
|--------|-------------|---------|
| -o DIR | Output directory | Current directory |
| -f FORMAT | Target format for conversion | mp3 |
| -q QUALITY | Quality: low, mid, high | mid |
| -h | Show help | – |

**Examples:**
```bash
# Convert all recovered files to MP3 (mid quality)
./Move-Recovered.sh

# Convert to high quality FLAC
./Move-Recovered.sh -f flac -q high

# Convert to medium quality MP4 video
./Move-Recovered.sh -f mp4 -q mid
```

---

## File Structure

When scripts run, they create the following hidden files in the output directory:
```
OUTPUT_DIR/
├── .downloaded_ids.txt          # Successfully downloaded from YouTube
├── .recovered_ids.txt           # Recovered from archives (Linux only)
├── .failed_ids.txt              # Failed (to be retried)
├── .permanently_failed_ids.txt  # Permanently unavailable (never retried)
├── .playlist_videos.txt         # All video IDs from playlist
├── .ytdlp_archive.txt           # yt-dlp internal download archive
├── .archive_recovered/          # Temporary folder for archive-recovered files (Linux only)
│   └── (recovered files before processing)
└── Artist - Song Name.mp3       # Your music files
```

**Log File Purposes**

| File                        | Purpose                                      |
|-----------------------------|----------------------------------------------|
| .downloaded_ids.txt         | Videos that downloaded successfully from YouTube |
| .recovered_ids.txt          | Videos recovered from archives (Linux only)  |
| .failed_ids.txt             | Videos that failed but may succeed later     |
| .permanently_failed_ids.txt | Videos not on YouTube - NEVER retried        |
| .playlist_videos.txt        | Complete list of video IDs from playlist     |
| .ytdlp_archive.txt          | yt-dlp's internal tracking (do not modify)   |
| .archive_recovered/         | Temporary storage for archive-recovered files|

---

## How Permanent Failure Tracking Works

1. **First attempt:** Script tries to download from YouTube
2. **If YouTube fails (and archive is disabled or unavailable):**
   - Video added to .permanently_failed_ids.txt
   - Future runs will skip all videos in this file automatically

This prevents wasting time on videos that truly don't exist anywhere.

**Note:** On Windows, archive recovery is not available. Videos that fail on YouTube are immediately marked as permanently failed.

---

## Internet Disconnection Handling

Both main scripts include automatic internet detection:
- Check before each download using ping to 8.8.8.8, 1.1.1.1, and curl to google.com
- If connection lost → Script pauses and waits
- Retries every 30 seconds until connection returns
- Resumes automatically when internet is restored

Example output:
```
⚠️  No internet connection detected
Waiting for connection to resume...
  Still waiting... (30s elapsed)
  Still waiting... (60s elapsed)
✓ Internet connection restored! Resuming downloads.
```

---

## Quality Selection Guide

**Audio Quality Comparison**

| Quality | Bitrate   | File Size (per 3 min) | Use Case                        |
|---------|-----------|-----------------------|----------------------------------|
| low     | ~80kbps   | ~2 MB                 | Speech, podcasts, mobile data    |
| mid     | ~192kbps  | ~4 MB                 | Music (recommended default)      |
| high    | ~320kbps  | ~7 MB                 | Archiving, high-end audio        |

**Video Quality Comparison**

| Quality | Resolution         | File Size (per 3 min) | Use Case                        |
|---------|--------------------|-----------------------|----------------------------------|
| low     | Worst available    | ~5-10 MB              | Mobile viewing, data saving      |
| mid     | Up to 480p         | ~15-30 MB             | Standard viewing (recommended)   |
| high    | Best (720p-4K)     | ~50-200+ MB           | Archiving, large screens         |

---

## Recommended Delays by Playlist Size

| Playlist Size      | Min Delay | Recommended | Safe Delay | Time (at Recommended) |
|--------------------|-----------|-------------|------------|-----------------------|
| 1-10 songs         | 0-2s      | 2s          | 5s         | < 1 minute            |
| 11-50 songs        | 2-3s      | 3s          | 5s         | 2-3 minutes           |
| 51-100 songs       | 3-5s      | 5s          | 8s         | 4-8 minutes           |
| 101-250 songs      | 5-8s      | 8s          | 10s        | 13-33 minutes         |
| 251-500 songs      | 8-10s     | 10s         | 12s        | 42-83 minutes         |
| 501-1,000 songs    | 10-12s    | 12s         | 15s        | 1.7-3.3 hours         |
| 1,001-2,000 songs  | 12-15s    | 15s         | 20s        | 4.2-8.3 hours         |
| 2,001-3,000 songs  | 15s       | 18s         | 20-25s     | 10-15 hours           |
| 3,001-5,000 songs  | 15-20s    | 18s         | 25s        | 15-25 hours           |
| 5,000+ songs       | 20-30s    | 25s         | 30+s       | 35-70 hours           |

**Risk Levels**

| Delay Range | Risk Level      | Best For                  |
|-------------|----------------|---------------------------|
| 0-2 seconds | High (IP ban)  | Testing only              |
| 3-5 seconds | Medium         | Small playlists (<100)    |
| 8-12 seconds| Low            | Most playlists            |
| 15-20 seconds| Very Low      | Large playlists (1,000+)  |
| 25+ seconds | Minimal        | Massive playlists (5,000+)|

---

## Complete Workflow Examples

**Linux/macOS (Full Features)**
```bash
# First download (overnight, high quality)
./Download-Playlist.sh -p "URL" -o "MyPlaylist" -q high -a -t 15

# Next day, retry any failures
cd MyPlaylist
../Retry-Failed.sh -q high -t 5

# Process any recovered files
../Move-Recovered.sh -q high

# Check permanently failed videos
cat .permanently_failed_ids.txt
```

**Windows (Basic Features)**
```powershell
# First download
.\Download-Playlist.ps1 -p "URL" -o "C:\Music" -q high -t 15

# Retry any failures
.\Retry-Failed.ps1 -o "C:\Music" -t 5

# Check permanently failed videos
Get-Content C:\Music\.permanently_failed_ids.txt
```

---

## Troubleshooting

**"ERROR: Could not extract video IDs"**
- Remove tracking parameters from URL (automatically handled by script)
- Ensure playlist is public or you're logged into Firefox
- Try the debug command:  
  `yt-dlp --cookies-from-browser firefox --flat-playlist --print "%(id)s" "URL"`

**Videos with hyphens in ID keep re-downloading**
- Fixed in latest version. The scripts now properly handle video IDs that start with hyphens (e.g., -_H5A1Xskjg).

**"n challenge solving failed" (Linux only)**
- Install Deno (required for archive recovery):  
  `curl -fsSL https://deno.land/install.sh | sh`

**Script won't retry permanently failed videos**
- Permanently failed videos go to .permanently_failed_ids.txt. To retry them anyway:  
  `sed -i '/VIDEO_ID/d' .permanently_failed_ids.txt`

**Internet keeps disconnecting**
- The script auto-pauses and resumes. Check your connection stability.

**Hidden files not visible**
- Use `ls -la` on Linux/macOS or `Get-ChildItem -Force` in PowerShell to see hidden files.

---

## Platform Differences

| Feature                    | Linux/macOS (Bash) | Windows (PowerShell) |
|----------------------------|--------------------|----------------------|
| Archive recovery (-a)      | ✅ Full support    | ❌ Not available     |
| Quality selection          | ✅ Full support    | ✅ Full support      |
| Hidden log files (.)       | ✅ Yes             | ✅ Yes               |
| Internet disconnection     | ✅ Yes             | ✅ Yes               |
| Permanent failure tracking | ✅ Yes             | ✅ Yes               |
| Hyphen ID handling         | ✅ Yes             | ✅ Yes               |
| yt-dlp integration         | ✅ Full            | ✅ Full              |
| Move-Recovered script      | ✅ Yes             | ❌ Not needed        |

For full features on Windows, consider using WSL (Windows Subsystem for Linux) to run the Bash scripts.

---

## Notes

- All scripts are idempotent – safe to re-run anytime
- Interrupt with Ctrl+C – progress saves automatically
- Hidden log files (starting with .) keep your directory clean
- Video IDs starting with hyphens are properly handled
- Permanently failed videos are never retried
- Windows PowerShell scripts have no archive recovery feature

---

## License

These scripts are for personal use only. Downloading copyrighted content may violate YouTube’s Terms of Service.

---

## Credits

- yt-dlp – YouTube downloading
- FFmpeg – Audio/video conversion
- GhostArchive – Video archiving (Linux only)
- Archive.org – Wayback Machine (Linux only)

---
