# Tak YouTube Playlist Tools


## Prerequisites

Before using these scripts, ensure you have the following installed on your system:

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) (YouTube downloader)
- [ffmpeg](https://ffmpeg.org/) (audio/video conversion)
- [curl](https://curl.se/) (HTTP requests)
- [deno](https://deno.com/) (JavaScript/TypeScript runtime, if you use any Deno scripts)
- Bash shell (most Linux distributions include this by default)

**Optional:**
- Firefox browser (for cookie extraction in some scripts)

### Installation

#### yt-dlp
```sh
python3 -m pip install -U yt-dlp
# or
sudo apt install yt-dlp
```

#### ffmpeg
```sh
sudo apt install ffmpeg
# or
sudo dnf install ffmpeg
# or
brew install ffmpeg
```

#### curl
```sh
sudo apt install curl
# or
sudo dnf install curl
# or
brew install curl
```

#### Deno
```sh
curl -fsSL https://deno.land/install.sh | sh
# or see https://deno.com/manual/getting_started/installation for other methods
```

#### Bash
Bash is included by default on most Linux distributions and macOS. On Windows, use [WSL](https://docs.microsoft.com/en-us/windows/wsl/) or Git Bash.

---

## Scripts Overview

### 1. `Download-Playlist.sh`
**Purpose:**  
Downloads all videos from a YouTube playlist, with options for output format, sleep interval, and archive recovery for unavailable videos.

**Usage:**
```sh
./Download-Playlist.sh -p PLAYLIST_URL [options]
```
**Options:**
- `-p URL`   YouTube playlist URL (required)
- `-o DIR`   Output directory (default: current directory)
- `-t SECONDS` Sleep interval between downloads (default: 11)
- `-f FORMAT` Output format: mp3, m4a, opus, aac, flac, wav, mp4, webm, mkv, avi, mov (default: mp3)
- `-a`     Enable archive recovery for unavailable videos
- `-h`     Show help

**Example:**
```sh
./Download-Playlist.sh -p "https://youtube.com/playlist?list=ABC123" -o "$HOME/Music" -f mp4 -a
```

---

### 2. `Retry-Failed.sh`
**Purpose:**  
Retries downloads for videos that previously failed, always enabling archive recovery. Useful for attempting to recover videos that were unavailable in the initial run.

**Usage:**
```sh
./Retry-Failed.sh [options]
```
**Options:**
- `-o DIR`   Output directory (default: current directory)
- `-t SECONDS` Sleep interval between retries (default: 11)
- `-f FORMAT` Output format (default: mp3)
- `-h`     Show help

**Example:**
```sh
./Retry-Failed.sh -o "$HOME/Music" -f opus
```

---

### 3. `Move-Recovered.sh`
**Purpose:**  
Processes files in the `archive_recovered` directory, moving or converting them to the main output directory in the desired format (default: mp3).

**Usage:**
```sh
./Move-Recovered.sh [options]
```
**Options:**
- `-o DIR`   Output directory (default: current directory)
- `-f FORMAT` Target format for conversion (default: mp3)
- `-h`     Show help

**Example:**
```sh
./Move-Recovered.sh -o "$HOME/Music/Tak" -f mp4
```

---


## Performance Tips

| Playlist Size     | Recommended Delay| Archive | Estimated Time  |
|-------------------|------------------|---------|-----------------|
| < 100 songs       | 2-5 seconds      | Optional| 5-15 minutes    |
| 100-500 songs     | 5-10 seconds     | Off     | 1-2 hours       |
| 500-2000 songs    | 10-15 seconds    | Off     | 6-10 hours      |
| 2000+ songs       | 15-30 seconds    | Off     | Overnight       |

---

## Log Files

- `downloaded_ids.txt`  List of successfully downloaded video IDs
- `failed_ids.txt`    List of failed video IDs
- `recovered_ids.txt`  List of video IDs recovered from archives
- `archive_recovered/`  Temporary directory for recovered files

---

## Notes

- Archive recovery attempts to fetch unavailable videos from GhostArchive, Wayback Machine, or Hobune.stream.
- All scripts are designed to be idempotent and can be safely re-run to resume or retry downloads.
