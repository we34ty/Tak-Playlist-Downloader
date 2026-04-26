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

### Installation (Linux/macOS)

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


## Windows Support and .bat Files

Windows users can use the provided `.bat` files as equivalents to the Bash scripts. The requirements are similar, but installation steps differ:

- **yt-dlp**: Download the Windows executable from [yt-dlp releases](https://github.com/yt-dlp/yt-dlp/releases/latest) and place it somewhere in your PATH (e.g., `C:\Windows\System32` or a folder added to PATH). Alternatively, use `pip install yt-dlp` if you have Python installed.
- **ffmpeg**: Download a Windows build from [ffmpeg.org/download.html](https://ffmpeg.org/download.html) and add the `bin` directory to your PATH.
- **curl**: Modern Windows 10/11 includes `curl` by default. If not, install [curl for Windows](https://curl.se/windows/).
- **jq**: Download the Windows executable from [https://stedolan.github.io/jq/download/](https://stedolan.github.io/jq/download/) and add it to your PATH.
- **Deno**: Run the PowerShell install command from [https://deno.com/manual/getting_started/installation](https://deno.com/manual/getting_started/installation):
  ```powershell
  iwr https://deno.land/install.ps1 -useb | iex
  ```
- **Bash**: Not required for `.bat` files. If you want to use Bash scripts, install [Git Bash](https://gitforwindows.org/) or enable [WSL](https://docs.microsoft.com/en-us/windows/wsl/).

**Important:**
- The Windows `.bat` scripts **do not support the `-a` (archive recovery) argument**. Archive recovery is only available in the Bash versions on Linux/macOS.
- All required executables (yt-dlp.exe, ffmpeg.exe, jq.exe, curl.exe, deno.exe) should be accessible from your command prompt (i.e., added to your PATH).
- Some `.bat` scripts may require minor adjustments for your environment (e.g., file paths, output directories).

---

---

## Scripts Overview


### 1. `Download-Playlist.sh` / `Download-Playlist.bat`
**Purpose:**  
Downloads all videos from a YouTube playlist, with options for output format and sleep interval. Archive recovery (`-a`) is only available in the Bash version.

**Linux/macOS Usage:**
```sh
./Download-Playlist.sh -p PLAYLIST_URL [options]
```
**Windows Usage:**
```bat
Download-Playlist.bat -p PLAYLIST_URL [options]
```
**Options:**
- `-p URL`   YouTube playlist URL (required)
- `-o DIR`   Output directory (default: current directory)
- `-t SECONDS` Sleep interval between downloads (default: 11)
- `-f FORMAT` Output format: mp3, m4a, opus, aac, flac, wav, mp4, webm, mkv, avi, mov (default: mp3)
- `-a`     Enable archive recovery for unavailable videos (**Linux/macOS only**)
- `-h`     Show help

**Examples:**
- Linux/macOS:
	```sh
	./Download-Playlist.sh -p "https://youtube.com/playlist?list=ABC123" -o "$HOME/Music" -f mp4 -a
	```
- Windows:
	```bat
	Download-Playlist.bat -p "https://youtube.com/playlist?list=ABC123" -o "%USERPROFILE%\Music" -f mp4
	```

---


### 2. `Retry-Failed.sh` / `Retry-Failed.bat`
**Purpose:**  
Retries downloads for videos that previously failed. Archive recovery is only available in the Bash version.

**Linux/macOS Usage:**
```sh
./Retry-Failed.sh [options]
```
**Windows Usage:**
```bat
Retry-Failed.bat [options]
```
**Options:**
- `-o DIR`   Output directory (default: current directory)
- `-t SECONDS` Sleep interval between retries (default: 11)
- `-f FORMAT` Output format (default: mp3)
- `-h`     Show help

**Examples:**
- Linux/macOS:
	```sh
	./Retry-Failed.sh -o "$HOME/Music" -f opus
	```
- Windows:
	```bat
	Retry-Failed.bat -o "%USERPROFILE%\Music" -f opus
	```

---


### 3. `Move-Recovered.sh` / `Move-Recovered.bat`
**Purpose:**  
Processes files in the `archive_recovered` directory, moving or converting them to the main output directory in the desired format (default: mp3). Archive recovery is only available in the Bash version.

**Linux/macOS Usage:**
```sh
./Move-Recovered.sh [options]
```
**Windows Usage:**
```bat
Move-Recovered.bat [options]
```
**Options:**
- `-o DIR`   Output directory (default: current directory)
- `-f FORMAT` Target format for conversion (default: mp3)
- `-h`     Show help

**Examples:**
- Linux/macOS:
	```sh
	./Move-Recovered.sh -o "$HOME/Music/Tak" -f mp4
	```
- Windows:
	```bat
	Move-Recovered.bat -o "%USERPROFILE%\Music\Tak" -f mp4
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
