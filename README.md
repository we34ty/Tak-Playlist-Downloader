# Tak YouTube Playlist Downloader

A comprehensive suite of bash scripts for downloading YouTube playlists with advanced features including archive recovery, permanent failure tracking, internet disconnection handling, and automatic resume capabilities.

## Features

- **Smart Downloading** – Downloads entire playlists with customizable formats (MP3, MP4, FLAC, etc.)
- **Permanent Failure Tracking** – Videos that fail on YouTube AND all archives are marked permanently failed and never retried
- **Internet Disconnection Handling** – Automatically pauses downloads when internet drops and resumes when connection returns
- **Archive Recovery** – Searches GhostArchive, Wayback Machine, Archive.org, and Hobune.stream for deleted/private videos
- **Resume Capability** – Interrupt and restart without re-downloading completed files
- **Duplicate Prevention** – Tracks downloaded, recovered, and permanently failed videos
- **Customizable Delays** – Configurable sleep intervals to avoid rate limiting
- **Cross-Platform** – Bash scripts for Linux/macOS, `.ps1` (PowerShell) and `.bat` files for Windows (PowerShell scripts recommended for Windows)

---

## Prerequisites

Before using these scripts, ensure you have the following installed:

### Required (All Platforms)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) – YouTube/downloader
- [ffmpeg](https://ffmpeg.org/) – Audio/video conversion
- [curl](https://curl.se/) – HTTP requests for archive checks

### For Archive Recovery (Linux/macOS only)
- [Deno](https://deno.com/) – JavaScript runtime for solving YouTube challenges

### For Windows `.bat` Scripts
- yt-dlp.exe, ffmpeg.exe, curl.exe must be in your PATH
- **PowerShell (.ps1) scripts are recommended for Windows.**
- **Archive recovery (`-a` flag) is NOT available in Windows version.**

### Installation (Linux/macOS)

```bash
# Install yt-dlp (standalone binary recommended)
sudo wget https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -O /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp

# Install ffmpeg
sudo apt install ffmpeg        # Debian/Ubuntu
sudo dnf install ffmpeg        # Fedora
brew install ffmpeg            # macOS

# Install curl (usually pre-installed)
sudo apt install curl

# Install Deno (required for archive recovery)
curl -fsSL https://deno.land/install.sh | sh
echo 'export PATH="$HOME/.deno/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Installation (Windows)

```powershell
# Using Chocolatey (recommended)
choco install yt-dlp ffmpeg curl

# Or manually download and add to PATH:
# - yt-dlp.exe: https://github.com/yt-dlp/yt-dlp/releases
# - ffmpeg.exe: https://www.gyan.dev/ffmpeg/builds/
# - curl is included in Windows 10/11
```

### PowerShell Scripts (Windows)

For best results on Windows, use the provided `.ps1` PowerShell scripts:

- Download-Playlist.ps1
- Retry-Failed.ps1
- Move-Recovered.ps1

Run them from PowerShell with the same options as the Bash scripts (see below for details). Archive recovery is not available in the Windows version.

---

## Scripts Overview

### 1. Download-Playlist.sh (Linux/macOS) / Download-Playlist.ps1 (Windows)

**Purpose:**
Main downloader. Downloads all videos from a YouTube playlist with format selection, delay configuration, and optional archive recovery.

**Key Features:**

    - Extracts all video IDs from playlist
    - Tracks downloaded, recovered, and permanently failed videos
    - Auto-pauses on internet disconnection
    - Marks videos as permanently failed if unavailable on YouTube AND all archives
    - Converts recovered files to target format automatically

**Usage:**
```bash
./Download-Playlist.sh -p PLAYLIST_URL [OPTIONS]   # Linux/macOS
```
```powershell
./Download-Playlist.ps1 -PlaylistUrl PLAYLIST_URL [-OutputDir DIR] [-SleepInterval SECONDS] [-Format mp3|mp4|flac|etc.]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| -p URL | YouTube playlist URL (required) | – |
| -o DIR | Output directory | Current directory |
| -t SECONDS | Sleep between downloads | 11 |
| -f FORMAT | Output format (mp3, mp4, flac, etc.) | mp3 |
| -a | Enable archive recovery (Linux/macOS only) | Disabled |
| -h | Show help | – |

**Examples:**
```bash
# Basic download as MP3 (Linux/macOS)
./Download-Playlist.sh -p "https://youtube.com/playlist?list=ABC123"
# Download as MP4 with 5s delay
./Download-Playlist.sh -p "URL" -o "$HOME/Videos" -t 5 -f mp4
```
```powershell
# Basic download as MP3 (Windows)
./Download-Playlist.ps1 -PlaylistUrl "https://youtube.com/playlist?list=ABC123"
# Download as MP4 with 5s delay
./Download-Playlist.ps1 -PlaylistUrl "URL" -OutputDir "C:\Videos" -SleepInterval 5 -Format mp4
```

### 2. Retry-Failed.sh (Linux/macOS) / Retry-Failed.ps1 (Windows)

**Purpose:**
Retries videos that failed during main download. Searches archives and permanently marks still-unavailable videos.

**Key Features:**

    - Retries failed videos from failed_ids.txt
    - Searches all archive sources for recovery
    - Marks permanently failed videos to skip future retries
    - Handles internet disconnection gracefully

**Usage:**
```bash
./Retry-Failed.sh [OPTIONS]   # Linux/macOS
```
```powershell
./Retry-Failed.ps1 [-OutputDir DIR] [-SleepInterval SECONDS] [-Format mp3|mp4|flac|etc.]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| -o DIR | Output directory | Current directory |
| -t SECONDS | Sleep between retries | 11 |
| -f FORMAT | Output format | mp3 |
| -h | Show help | – |

**Examples:**
```bash
# Retry failed in current directory (Linux/macOS)
./Retry-Failed.sh
# Retry in specific folder with 5s delay
./Retry-Failed.sh -o "$HOME/Music" -t 5
# Retry as MP4
./Retry-Failed.sh -f mp4
```
```powershell
# Retry failed in current directory (Windows)
./Retry-Failed.ps1
# Retry in specific folder with 5s delay
./Retry-Failed.ps1 -OutputDir "C:\Music" -SleepInterval 5
# Retry as MP4
./Retry-Failed.ps1 -Format mp4
```

### 3. Move-Recovered.sh (Linux/macOS) / Move-Recovered.ps1 (Windows)

**Purpose:**
Processes files in archive_recovered folder, moves or converts them to the main output directory.

**Usage:**
```bash
./Move-Recovered.sh [OPTIONS]   # Linux/macOS
```
```powershell
./Move-Recovered.ps1 [-OutputDir DIR] [-Format mp3|mp4|flac|etc.]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| -o DIR | Output directory | Current directory |
| -f FORMAT | Target format for conversion | mp3 |
| -h | Show help | – |

**Examples:**
```bash
# Process recovered files in current directory (Linux/macOS)
./Move-Recovered.sh
# Convert all recovered files to FLAC
./Move-Recovered.sh -f flac
# Process specific directory
./Move-Recovered.sh -o "$HOME/Music/Tak" -f mp4
```
```powershell
# Process recovered files in current directory (Windows)
./Move-Recovered.ps1
# Convert all recovered files to FLAC
./Move-Recovered.ps1 -Format flac
# Process specific directory
./Move-Recovered.ps1 -OutputDir "C:\Music\Tak" -Format mp4
```

---

## File Structure & Logs

When scripts run, they create the following files in the output directory:

```
OUTPUT_DIR/
├── downloaded_ids.txt          # Successfully downloaded from YouTube
├── recovered_ids.txt           # Recovered from archives
├── failed_ids.txt              # Failed (to be retried)
├── permanently_failed_ids.txt  # Permanently unavailable (never retried)
├── playlist_videos.txt         # All video IDs from playlist
├── archive_recovered/          # Temporary folder for recovered files
│   └── (recovered files before processing)
└── (Your MP3/MP4 files)        # "Artist - Song Name.ext"
```

### Log File Purposes

| File | Purpose |
|------|---------|
| downloaded_ids.txt | Videos that downloaded successfully |
| recovered_ids.txt | Videos recovered from archives |
| failed_ids.txt | Videos that failed but may succeed later |
| permanently_failed_ids.txt | Videos not on YouTube OR any archive - NEVER retried |
| playlist_videos.txt | Complete list of video IDs from playlist |

---

## How Permanent Failure Tracking Works

1. **First attempt:** Script tries to download from YouTube
2. **If YouTube fails and -a is enabled, it searches:**
    - GhostArchive
    - Archive.org
    - Wayback Machine
    - Hobune.stream
3. **If ALL sources fail → Video added to permanently_failed_ids.txt**
4. **Future runs will skip all videos in this file automatically**

This prevents wasting time on videos that truly don't exist anywhere.

---

## Internet Disconnection Handling

Both main scripts include automatic internet detection:

    - Check before each download using ping to 8.8.8.8, 1.1.1.1, and curl to google.com
    - If connection lost → Script pauses and waits
    - Retries every 30 seconds until connection returns
    - Maximum wait: 1 hour (exits gracefully after that)
    - Resumes automatically when internet is restored

```
⚠️  No internet connection detected
Waiting for connection to resume...
  Still waiting... (30s elapsed)
  Still waiting... (60s elapsed)
✓ Internet connection restored! Resuming downloads.
```

---

## Performance Guide

### Recommended Delays by Playlist Size


| Playlist Size    | Min Delay | Recommended Delay | Safe Delay | Time (at Recommended Delay) |
|------------------|-----------|------------------|------------|----------------------------|
| 1-10 songs       | 0-2s      | 2s               | 5s         | < 1 minute                 |
| 11-50 songs      | 2-3s      | 3s               | 5s         | 2-3 minutes                |
| 51-100 songs     | 3-5s      | 5s               | 8s         | 4-8 minutes                |
| 101-250 songs    | 5-8s      | 8s               | 10s        | 13-33 minutes              |
| 251-500 songs    | 8-10s     | 10s              | 12s        | 42-83 minutes              |
| 501-1,000 songs  | 10-12s    | 12s              | 15s        | 1.7-3.3 hours              |
| 1,001-2,000 songs| 12-15s    | 15s              | 20s        | 4.2-8.3 hours              |
| 2,001-3,000 songs| 15s       | 18s              | 20-25s     | 10-15 hours                |
| 3,001-5,000 songs| 15-20s    | 18s              | 25s        | 15-25 hours                |
| 5,000+ songs     | 20-30s    | 25s              | 30+s       | 35-70 hours                |

#### Risk Levels

| Delay Range | Risk Level | Best For |
|-------------|-----------|----------|
| 0-2 seconds | High (IP ban likely) | Testing only |
| 3-5 seconds | Medium | Small playlists (<100) |
| 8-12 seconds | Low | Most playlists |
| 15-20 seconds | Very Low | Large playlists (1,000+) |
| 25+ seconds | Minimal | Massive playlists (5,000+) |

---

## Archive Recovery Sources

When -a is enabled, the scripts search:

| Source | Content Type | Success Rate |
|--------|--------------|--------------|
| GhostArchive | Direct video/audio files | High |
| Archive.org | User-uploaded backups | Medium |
| Wayback Machine | Webpage archives (sometimes with video) | Low-Medium |
| Hobune.stream | Community video archive | Medium |

Note: Archive.org often stores multiple resolutions of the same video. The scripts now download only the best quality to avoid duplicates.

---

## Windows Support Limitations


| Feature | Linux/macOS | Windows (.ps1 PowerShell) |
|---------|-------------|--------------------------|
| Archive recovery (-a) | ✅ Full support | ❌ Not available |
| Internet disconnection handling | ✅ Yes | ✅ Yes |
| Permanent failure tracking | ✅ Yes | ✅ Yes |
| Rate limiting | ✅ Yes | ✅ Yes |
| Format conversion | ✅ Full | ✅ Full |
| Cookie extraction | ✅ Firefox/Chrome | ✅ Firefox |

For full features on Windows, use WSL (Windows Subsystem for Linux) to run the Bash scripts.

---

## Complete Workflow Examples

**Basic Download (MP3, no archive)**

```bash
./Download-Playlist.sh -p "https://youtube.com/playlist?list=ABC123" -o "Music"
```

**Download with Archive Recovery**
```bash
./Download-Playlist.sh -p "URL" -o "Music" -a -t 12
```

**Download as MP4 with Archive Recovery**
```bash
./Download-Playlist.sh -p "URL" -o "Videos" -f mp4 -a -t 15
```

**Retry Failed Downloads**
```bash
./Retry-Failed.sh -o "Music" -t 5
```

**Complete Pipeline for Large Playlist**
```bash
# First download (overnight)
./Download-Playlist.sh -p "URL" -o "MyPlaylist" -t 15 -a

# Next day, retry any failures
cd MyPlaylist
../Retry-Failed.sh -t 5

# Process any recovered files
../Move-Recovered.sh

# Check permanently failed videos
cat permanently_failed_ids.txt
```

---

## Troubleshooting

**"ERROR: Could not extract video IDs"**

    - Remove tracking parameters from URL (&si=... gets removed automatically)
    - Ensure playlist is public or you're logged into Firefox
    - Try the debug command: yt-dlp --cookies-from-browser firefox --flat-playlist --print "%(id)s" "URL"

**"n challenge solving failed"**

    Install Deno (archive recovery requires it):
    ```bash
    curl -fsSL https://deno.land/install.sh | sh
    ```

**Video downloads multiple resolutions from Archive.org**

    Fixed in latest version – now uses --no-playlist and -f bestvideo+bestaudio

**Script won't retry permanently failed videos**

    Permanently failed videos go to permanently_failed_ids.txt. To retry them anyway:
    ```bash
    # Remove from permanently failed list
    sed -i '/VIDEO_ID/d' permanently_failed_ids.txt
    ```

**Internet keeps disconnecting**

    The script auto-pauses and resumes. Check your connection stability.

---

## Notes

    - All scripts are idempotent – safe to re-run anytime
    - Interrupt with Ctrl+C – progress saves automatically
    - Archive recovery (-a) requires Deno and active internet
    - Permanent failure prevents infinite retry loops
    - Windows .bat files have reduced functionality – use WSL for full features

---

## License

These scripts are for personal use only. Downloading copyrighted content may violate YouTube's Terms of Service.

---

## Credits

    - yt-dlp – YouTube downloading
    - FFmpeg – Audio/video conversion
    - GhostArchive – Video archiving
    - Archive.org – Wayback Machine
