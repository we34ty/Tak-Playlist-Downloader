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
- **Cross-Platform** – Bash scripts for Linux/macOS, `.bat` files for Windows (with limitations)

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
- **Archive recovery (`-a` flag) is NOT available in Windows version**

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

---

## Scripts Overview

### 1. Download-Playlist.sh (Linux/macOS) / Download-Playlist.bat (Windows)

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
./Download-Playlist.sh -p PLAYLIST_URL [OPTIONS]
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
# Basic download as MP3
./Download-Playlist.sh -p "https://youtube.com/playlist?list=ABC123"

# Download as MP4 with 5s delay
./Download-Playlist.sh -p "URL" -o "$HOME/Videos" -t 5 -f mp4

# Enable archive recovery for deleted videos
./Download-Playlist.sh -p "URL" -o "$HOME/Music" -a

# High-quality audio with archive recovery
./Download-Playlist.sh -p "URL" -f flac -t 15 -a
```

### 2. Retry-Failed.sh (Linux/macOS) / Retry-Failed.bat (Windows)

**Purpose:**
Retries videos that failed during main download. Searches archives and permanently marks still-unavailable videos.

**Key Features:**

    - Retries failed videos from failed_ids.txt
    - Searches all archive sources for recovery
    - Marks permanently failed videos to skip future retries
    - Handles internet disconnection gracefully

**Usage:**
```bash
./Retry-Failed.sh [OPTIONS]
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
# Retry failed in current directory
./Retry-Failed.sh

# Retry in specific folder with 5s delay
./Retry-Failed.sh -o "$HOME/Music" -t 5

# Retry as MP4
./Retry-Failed.sh -f mp4
```

### 3. Move-Recovered.sh (Linux/macOS) / Move-Recovered.bat (Windows)

**Purpose:**
Processes files in archive_recovered folder, moves or converts them to the main output directory.

**Usage:**
```bash
./Move-Recovered.sh [OPTIONS]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| -o DIR | Output directory | Current directory |
| -f FORMAT | Target format for conversion | mp3 |
| -h | Show help | – |

**Examples:**
```bash
# Process recovered files in current directory
./Move-Recovered.sh

# Convert all recovered files to FLAC
./Move-Recovered.sh -f flac

# Process specific directory
./Move-Recovered.sh -o "$HOME/Music/Tak" -f mp4
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

| Playlist Size | Min Delay | Recommended | Safe Delay | Time (10s delay) |
|--------------|-----------|-------------|------------|------------------|
| 1-10 songs   | 0-2s      | 2s          | 5s         | < 1 min          |
| 11-50 songs  | 2-3s      | 3s          | 5s         | 5-10 min         |
| 51-100 songs | 3-5s      | 5s          | 8s         | 15-25 min        |
| 101-250      | 5-8s      | 8s          | 10s        | 30-45 min        |
| 251-500      | 8-10s     | 10s         | 12s        | 1.5-2 hrs        |
| 501-1,000    | 10-12s    | 12s         | 15s        | 3-4 hrs          |
| 1,001-2,000  | 12-15s    | 15s         | 20s        | 6-8 hrs          |
| 2,001-3,000  | 15s       | 15-18s      | 20-25s     | 9-12 hrs         |
| 3,001-5,000  | 15-20s    | 18s         | 25s        | 15-20 hrs        |
| 5,000+ songs | 20-30s    | 25s         | 30+s       | 35+ hrs          |

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

| Feature | Linux/macOS | Windows (.bat) |
|---------|-------------|---------------|
| Archive recovery (-a) | ✅ Full support | ❌ Not available |
| Internet disconnection handling | ✅ Yes | ❌ Not implemented |
| Permanent failure tracking | ✅ Yes | ❌ Not implemented |
| Rate limiting | ✅ Yes | ✅ Yes |
| Format conversion | ✅ Full | ✅ Basic (MP3/MP4 only) |
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
