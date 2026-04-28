# ========== ARGUMENT PARSING (MUST BE FIRST) ==========
param(
	[string]$p,
	[string]$o,
	[int]$t,
	[string]$f,
	[string]$q,
	[switch]$h
)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# ========== FFMPEG CHECK & AUTO-DOWNLOAD ==========
$FfmpegExe = Join-Path $ScriptDir 'ffmpeg.exe'
if (-not (Test-Path $FfmpegExe)) {
	Write-Host "[!] ffmpeg.exe not found. Downloading latest static Windows build..."
	$ffmpegZipUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
	$ffmpegZip = Join-Path $ScriptDir 'ffmpeg-release-essentials.zip'
	try {
		Invoke-WebRequest -Uri $ffmpegZipUrl -OutFile $ffmpegZip -UseBasicParsing
		Write-Host "[OK] ffmpeg zip downloaded. Extracting..."
		Add-Type -AssemblyName System.IO.Compression.FileSystem
		[System.IO.Compression.ZipFile]::ExtractToDirectory($ffmpegZip, $ScriptDir)
		# Find ffmpeg.exe in extracted folders
		$ffmpegFound = Get-ChildItem -Path $ScriptDir -Recurse -Filter ffmpeg.exe | Select-Object -First 1
		if ($ffmpegFound) {
			Move-Item -Force $ffmpegFound.FullName $FfmpegExe
			Write-Host "[OK] ffmpeg.exe extracted and moved."
		} else {
			Write-Host "ERROR: ffmpeg.exe not found after extraction."
			exit 1
		}
		Remove-Item $ffmpegZip -Force
		# Optionally remove extracted folders
		Get-ChildItem -Path $ScriptDir -Directory | Where-Object { $_.Name -like 'ffmpeg-*' } | Remove-Item -Recurse -Force
	} catch {
		Write-Host "ERROR: Failed to download or extract ffmpeg. Please check your internet connection or download manually from $ffmpegZipUrl"
		exit 1
	}
}
if (-not (Test-Path $FfmpegExe)) {
	Write-Host "ERROR: ffmpeg.exe is required but could not be installed. Exiting."
	exit 1
}

# ========== YT-DLP CHECK & AUTO-DOWNLOAD ==========
$YtDlpExe = Join-Path $ScriptDir 'yt-dlp.exe'
if (-not (Test-Path $YtDlpExe)) {
	Write-Host "[!] yt-dlp.exe not found. Downloading latest version..."
	$ytDlpUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
	try {
		Invoke-WebRequest -Uri $ytDlpUrl -OutFile $YtDlpExe -UseBasicParsing
		Write-Host "[OK] yt-dlp.exe downloaded successfully."
	} catch {
		Write-Host "ERROR: Failed to download yt-dlp.exe. Please check your internet connection or download manually from $ytDlpUrl"
		exit 1
	}
}
# ========== FFMPEG CHECK & AUTO-DOWNLOAD ==========
$FfmpegExe = Join-Path $ScriptDir 'ffmpeg.exe'
if (-not (Test-Path $FfmpegExe)) {
	Write-Host "[!] ffmpeg.exe not found. Downloading latest static Windows build..."
	$ffmpegZipUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
	$ffmpegZip = Join-Path $ScriptDir 'ffmpeg-release-essentials.zip'
	try {
		Invoke-WebRequest -Uri $ffmpegZipUrl -OutFile $ffmpegZip -UseBasicParsing
		Write-Host "[OK] ffmpeg zip downloaded. Extracting..."
		Add-Type -AssemblyName System.IO.Compression.FileSystem
		[System.IO.Compression.ZipFile]::ExtractToDirectory($ffmpegZip, $ScriptDir)
		# Find ffmpeg.exe in extracted folders
		$ffmpegFound = Get-ChildItem -Path $ScriptDir -Recurse -Filter ffmpeg.exe | Select-Object -First 1
		if ($ffmpegFound) {
			Move-Item -Force $ffmpegFound.FullName $FfmpegExe
			Write-Host "[OK] ffmpeg.exe extracted and moved."
		} else {
			Write-Host "ERROR: ffmpeg.exe not found after extraction."
			exit 1
		}
		Remove-Item $ffmpegZip -Force
		# Optionally remove extracted folders
		Get-ChildItem -Path $ScriptDir -Directory | Where-Object { $_.Name -like 'ffmpeg-*' } | Remove-Item -Recurse -Force
	} catch {
		Write-Host "ERROR: Failed to download or extract ffmpeg. Please check your internet connection or download manually from $ffmpegZipUrl"
		exit 1
	}
}
if (-not (Test-Path $FfmpegExe)) {
	Write-Host "ERROR: ffmpeg.exe is required but could not be installed. Exiting."
	exit 1
}

# ========== YT-DLP CHECK & AUTO-DOWNLOAD ==========
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$YtDlpExe = Join-Path $ScriptDir 'yt-dlp.exe'
if (-not (Test-Path $YtDlpExe)) {
	Write-Host "[!] yt-dlp.exe not found. Downloading latest version..."
	$ytDlpUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
	try {
		Invoke-WebRequest -Uri $ytDlpUrl -OutFile $YtDlpExe -UseBasicParsing
		Write-Host "[OK] yt-dlp.exe downloaded successfully."
	} catch {
		Write-Host "ERROR: Failed to download yt-dlp.exe. Please check your internet connection or download manually from $ytDlpUrl"
		exit 1
	}
}

# ========== DEFAULT CONFIGURATION ==========
$OutputDir = Get-Location
$SleepInterval = 11
$Format = 'mp3'
$Quality = 'mid'
$PlaylistUrl = $null

# ========== COLOR CONSTANTS (Write-Host Wrappers) ========== 
$Red     = { param($msg) Write-Host $msg -ForegroundColor Red }
$Green   = { param($msg) Write-Host $msg -ForegroundColor Green }
$Yellow  = { param($msg) Write-Host $msg -ForegroundColor Yellow }
$Blue    = { param($msg) Write-Host $msg -ForegroundColor Blue }
$Cyan    = { param($msg) Write-Host $msg -ForegroundColor Cyan }
$Magenta = { param($msg) Write-Host $msg -ForegroundColor Magenta }

function Show-Help {
	Write-Host "Usage: .\Download-Playlist.ps1 -p <PLAYLIST_URL> [-o <OUTPUT_DIR>] [-t <SECONDS>] [-f <FORMAT>] [-q <QUALITY>] [-h]" -ForegroundColor Cyan
	Write-Host ""
	Write-Host "Required:"
	Write-Host "  -p <URL>        YouTube playlist URL"
	Write-Host ""
	Write-Host "Options:"
	Write-Host "  -o <DIR>        Output directory (default: current directory)"
	Write-Host "  -t <SECONDS>    Sleep between downloads (default: 11, 0 = no delay)"
	Write-Host "  -f <FORMAT>     Output format: mp3, m4a, opus, flac, mp4, webm, etc. (default: mp3)"
	Write-Host "  -q <QUALITY>    Quality: low, mid, high (default: mid)"
	Write-Host "                Audio: low(80k), mid(192k), high(320k)"
	Write-Host "                Video: low(worst), mid(480p), high(best)"
	Write-Host "  -h             Show this help"
}

if ($h) { Show-Help; exit 0 }
if ($p) { $PlaylistUrl = $p }
if ($o) { $OutputDir = $o }
if ($t) { $SleepInterval = $t }
if ($f) { $Format = $f }
if ($q) { $Quality = $q }

if (-not $PlaylistUrl) {
	& $Red "ERROR: Playlist URL is required"
	Show-Help
	exit 1
}

if ($Quality -notin @('low','mid','high')) {
	& $Red "ERROR: Quality must be low, mid, or high"
	exit 1
}

if ($SleepInterval -lt 0 -or ($SleepInterval -isnot [int])) {
	& $Red "ERROR: Sleep interval must be a number"
	exit 1
}

# ========== INTERNET CHECK ==========
function Test-Internet {
	try {
		$null = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction Stop
		return $true
	} catch {
		return $false

	}
}

function Wait-ForInternet {
	$waitTime = 30
	$maxWait = 3600
	$elapsed = 0
	& $Yellow "[!] No internet connection detected"
	& $Yellow "Waiting for connection to resume..."
	while (-not (Test-Internet)) {
		Start-Sleep -Seconds $waitTime
		$elapsed += $waitTime
		if ($elapsed -ge $maxWait) {
			& $Red "No internet connection after 1 hour. Exiting."
			exit 1
		}
		& $Blue "  Still waiting... ($elapsed s elapsed)"
	}
	& $Green "[OK] Internet connection restored! Resuming downloads."
	Start-Sleep -Seconds 5
}

# ========== FORMAT & QUALITY ==========
$AudioFormats = 'mp3','m4a','aac','flac','wav','opus'
$VideoFormats = 'mp4','webm','mkv','avi','mov'
$FormatLower = $Format.ToLower()
if ($AudioFormats -contains $FormatLower) {
	$DownloadType = 'audio'
	$OutputTemplate = '%(uploader)s - %(title)s.%(ext)s'
	& $Blue "Format: $FormatLower (audio only)"
} elseif ($VideoFormats -contains $FormatLower) {
	$DownloadType = 'video'
	$OutputTemplate = '%(uploader)s - %(title)s.%(ext)s'
	& $Blue "Format: $FormatLower (video + audio)"
} else {
	& $Red "ERROR: Unsupported format '$Format'"
	exit 1
}

switch ($FormatLower) {
	{ $AudioFormats -contains $_ } {
		switch ($Quality) {
			'low'  { $YtdlpArgs = "-f bestaudio -x --audio-format $FormatLower --audio-quality 5" }
			'mid'  { $YtdlpArgs = "-f bestaudio -x --audio-format $FormatLower --audio-quality 2" }
			'high' { $YtdlpArgs = "-f bestaudio -x --audio-format $FormatLower --audio-quality 0" }
			default { $YtdlpArgs = "-f bestaudio -x --audio-format $FormatLower --audio-quality 2" }
		}
		& $Blue "Audio quality: $Quality ($FormatLower)"
	}
	{ $VideoFormats -contains $_ } {
		switch ($Quality) {
			'low'  { $YtdlpArgs = "-f worstvideo+worstaudio --merge-output-format $FormatLower" }
			'mid'  { $YtdlpArgs = "-f bestvideo[height<=480]+bestaudio/best[height<=480] --merge-output-format $FormatLower" }
			'high' { $YtdlpArgs = "-f bestvideo+bestaudio --merge-output-format $FormatLower" }
			default { $YtdlpArgs = "-f bestvideo+bestaudio --merge-output-format $FormatLower" }
		}
		& $Blue "Video quality: $Quality"
	}
}

# ========== CREATE OUTPUT DIRECTORY ==========
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
Set-Location $OutputDir

# ========== LOG FILES ==========
$LogFile = ".downloaded_ids.txt"
$FailedLog = ".failed_ids.txt"
$PermanentlyFailedLog = ".permanently_failed_ids.txt"
$VideoIdsFile = ".playlist_videos.txt"
foreach ($file in @($LogFile, $FailedLog, $PermanentlyFailedLog)) { if (-not (Test-Path $file)) { New-Item $file -ItemType File | Out-Null } }

# ========== EXTRACT VIDEO IDS ==========
& $Green "========================================="
& $Green "Tak Playlist Downloader"
& $Green "========================================="
Write-Host "Output directory: $OutputDir"
Write-Host "Format: $FormatLower ($DownloadType)"
Write-Host "Quality: $Quality"
Write-Host "Delay: ${SleepInterval}s"
Write-Host ""

if (-not (Test-Internet)) { Wait-ForInternet }

& $Blue "Fetching playlist..."
Remove-Item $VideoIdsFile -ErrorAction SilentlyContinue
& $YtDlpExe --cookies-from-browser firefox --flat-playlist --print "%(id)s" $PlaylistUrl | Set-Content $VideoIdsFile
if (-not (Get-Content $VideoIdsFile | Where-Object { $_.Trim() })) {
	& $YtDlpExe --cookies-from-browser firefox --extractor-args youtubetab:skip=authcheck --flat-playlist --print "%(id)s" $PlaylistUrl | Set-Content $VideoIdsFile
}
if (-not (Get-Content $VideoIdsFile | Where-Object { $_.Trim() })) {
	& $Red "ERROR: Could not extract video IDs"
	exit 1
}

$VideoIds = Get-Content $VideoIdsFile | Where-Object { $_.Trim() }
$Total = $VideoIds.Count
$DownloadedCount = @(Select-String -Path $LogFile -Pattern "^.*$" | ForEach-Object { $_.Line } | Where-Object { $VideoIds -contains $_ }).Count
$PermanentlyFailedCount = @(Select-String -Path $PermanentlyFailedLog -Pattern "^.*$" | ForEach-Object { $_.Line } | Where-Object { $VideoIds -contains $_ }).Count
$Remaining = $Total - $DownloadedCount - $PermanentlyFailedCount
if ($Remaining -lt 0) { $Remaining = 0 }

Write-Host "Total videos: $Total"
Write-Host "Downloaded (in log): $DownloadedCount"
Write-Host "Permanently failed: $PermanentlyFailedCount"
Write-Host "Remaining: $Remaining"
Write-Host ""

# ========== DOWNLOAD LOOP ==========
$Processed = 0
$YoutubeSuccess = 0
$FailedVideos = 0
$SkippedPermanent = 0
$SkippedAlready = 0

foreach ($video_id in $VideoIds) {
	$video_id = $video_id.Trim()
	if (-not $video_id) { continue }
	$Processed++
	if (Select-String -Path $PermanentlyFailedLog -Pattern "^$video_id$" -Quiet) {
		Write-Host "[$($Processed)/$Total] SKIP: $video_id (permanently failed)"
		$SkippedPermanent++
		continue
	}
	if (Select-String -Path $LogFile -Pattern "^$video_id$" -Quiet) {
		Write-Host "[$($Processed)/$Total] SKIP: $video_id (already downloaded)"
		$SkippedAlready++
		continue
	}
	Write-Host ""
	& $Yellow "[$($Processed)/$Total] DOWNLOADING: $video_id"
	if (-not (Test-Internet)) { Wait-ForInternet }
	# Build yt-dlp argument array
	$args = @()
	$args += '--cookies-from-browser'; $args += 'firefox'
	$args += '--extractor-args'; $args += 'youtubetab:skip=authcheck'
	foreach ($part in $YtdlpArgs -split ' ') { if ($part) { $args += $part } }
	$args += '--embed-thumbnail'
	$args += '--add-metadata'
	$args += '--output'; $args += $OutputTemplate
	$args += '--no-overwrites'
	$args += '--continue'
	$args += "https://youtube.com/watch?v=$video_id"
	$result = & $YtDlpExe @args
	if ($LASTEXITCODE -eq 0) {
		& $Green "  [OK] Success - added to log"
		Add-Content $LogFile $video_id
		$YoutubeSuccess++
	} else {
		& $Red "  [X] YouTube failed"
		& $Yellow "  -> Marked as failed"
		Add-Content $FailedLog $video_id
		$FailedVideos++
	}
	if ($SleepInterval -gt 0 -and $Processed -lt $Total) {
		& $Blue "  Waiting ${SleepInterval}s..."
		Start-Sleep -Seconds $SleepInterval
	}
}

# ========== SUMMARY ==========
Write-Host ""
& $Green "========================================="
& $Green "COMPLETE!"
& $Green "========================================="
Write-Host "Total videos: $Total"
Write-Host ""
& $Green "[OK] Downloaded: $YoutubeSuccess"
& $Blue "- Skipped (already in log): $SkippedAlready"
& $Blue "- Skipped (permanently failed): $SkippedPermanent"
& $Red "[X] Newly failed: $FailedVideos"
Write-Host ""
Write-Host "Files saved to: $OutputDir"
