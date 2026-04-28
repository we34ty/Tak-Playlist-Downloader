# ========== ARGUMENT PARSING (MUST BE FIRST) ==========
param(
	[string]$p,
	[string]$o,
	[int]$t,
	[string]$f,
	[string]$q,
	[switch]$a,
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
		$ffmpegFound = Get-ChildItem -Path $ScriptDir -Recurse -Filter ffmpeg.exe | Select-Object -First 1
		if ($ffmpegFound) {
			Move-Item -Force $ffmpegFound.FullName $FfmpegExe
			Write-Host "[OK] ffmpeg.exe extracted and moved."
		} else {
			Write-Host "ERROR: ffmpeg.exe not found after extraction."
			exit 1
		}
		Remove-Item $ffmpegZip -Force
		Get-ChildItem -Path $ScriptDir -Directory | Where-Object { $_.Name -like 'ffmpeg-*' } | Remove-Item -Recurse -Force
	} catch {
		Write-Host "ERROR: Failed to download or extract ffmpeg."
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
		Write-Host "ERROR: Failed to download yt-dlp.exe."
		exit 1
	}
}

# ========== DEFAULT CONFIGURATION ==========
$OutputDir = Get-Location
$SleepInterval = 11
$Format = 'mp3'
$Quality = 'mid'
$PlaylistUrl = $null
$EnableArchive = $false
$ConfigFile = ".download_config.txt"

# ========== COLOR FUNCTIONS ========== 
function Write-Red { Write-Host $args -ForegroundColor Red }
function Write-Green { Write-Host $args -ForegroundColor Green }
function Write-Yellow { Write-Host $args -ForegroundColor Yellow }
function Write-Blue { Write-Host $args -ForegroundColor Blue }
function Write-Cyan { Write-Host $args -ForegroundColor Cyan }
function Write-Magenta { Write-Host $args -ForegroundColor Magenta }

function Show-Help {
	Write-Host "Usage: .\Download-Playlist.ps1 -p <PLAYLIST_URL> [-o <OUTPUT_DIR>] [-t <SECONDS>] [-f <FORMAT>] [-q <QUALITY>] [-a] [-h]" -ForegroundColor Cyan
	Write-Host ""
	Write-Host "Required (first run only):"
	Write-Host "  -p <URL>        YouTube playlist URL"
	Write-Host ""
	Write-Host "Options:"
	Write-Host "  -o <DIR>        Output directory (default: current directory)"
	Write-Host "  -t <SECONDS>    Sleep between downloads (default: 11, 0 = no delay)"
	Write-Host "  -f <FORMAT>     Output format: mp3, m4a, opus, flac, mp4, webm, etc. (default: mp3)"
	Write-Host "  -q <QUALITY>    Quality: low, mid, high (default: mid)"
	Write-Host "                Audio: low(80k), mid(192k), high(320k)"
	Write-Host "                Video: low(worst), mid(480p), high(best)"
	Write-Host "  -a              Enable archive recovery for deleted videos"
	Write-Host "  -h             Show this help"
	Write-Host ""
	Write-Host "Note: Settings are saved in .download_config.txt in the output directory."
	Write-Host "      Subsequent runs without -p will use saved playlist URL."
	Write-Host "      Retry-Failed.ps1 and Move-Recovered.ps1 share this configuration."
}

# ========== FUNCTION TO LOAD SAVED CONFIGURATION ==========
function Load-SavedConfig {
	param([string]$configPath)
	
	if (Test-Path $configPath) {
		Write-Blue "Loading saved configuration from: $configPath"
		$config = Get-Content $configPath -Raw | ConvertFrom-Json
		return $config
	}
	return $null
}

# ========== FUNCTION TO SAVE CONFIGURATION ==========
function Save-Config {
	param(
		[string]$configPath,
		[string]$playlistUrl,
		[string]$outputDir,
		[int]$sleepInterval,
		[string]$format,
		[string]$quality,
		[bool]$enableArchive
	)
	
	$config = @{
		PlaylistUrl = $playlistUrl
		OutputDir = $outputDir
		SleepInterval = $sleepInterval
		Format = $format
		Quality = $quality
		EnableArchive = $enableArchive
		LastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
	}
	
	$config | ConvertTo-Json | Set-Content $configPath
	Write-Blue "Configuration saved to: $configPath"
}

# ========== PARSE COMMAND LINE ARGUMENTS ==========
$HAS_P = $false
$HAS_O = $false
$HAS_T = $false
$HAS_F = $false
$HAS_Q = $false
$HAS_A = $false

# Parse manually to track which arguments were provided
$argList = @($MyInvocation.MyCommand.Path) + $args
for ($i = 0; $i -lt $args.Length; $i++) {
	switch ($args[$i]) {
		'-p' { $HAS_P = $true; $PlaylistUrl = $args[$i+1] }
		'-o' { $HAS_O = $true; $OutputDir = $args[$i+1] }
		'-t' { $HAS_T = $true; $SleepInterval = [int]$args[$i+1] }
		'-f' { $HAS_F = $true; $Format = $args[$i+1] }
		'-q' { $HAS_Q = $true; $Quality = $args[$i+1] }
		'-a' { $HAS_A = $true; $EnableArchive = $true }
		'-h' { Show-Help; exit 0 }
	}
}

# ========== CHECK FOR SAVED CONFIGURATION IF NO -p PROVIDED ==========
if (-not $HAS_P) {
	$configPathToCheck = Join-Path (Get-Location) $ConfigFile
	if ($HAS_O) {
		$configPathToCheck = Join-Path $OutputDir $ConfigFile
	}
	
	$savedConfig = Load-SavedConfig -configPath $configPathToCheck
	
	if ($savedConfig) {
		Write-Green "[INFO] Found saved configuration from: $($savedConfig.LastUpdated)"
		$PlaylistUrl = $savedConfig.PlaylistUrl
		if (-not $HAS_O) { $OutputDir = $savedConfig.OutputDir }
		if (-not $HAS_T) { $SleepInterval = $savedConfig.SleepInterval }
		if (-not $HAS_F) { $Format = $savedConfig.Format }
		if (-not $HAS_Q) { $Quality = $savedConfig.Quality }
		if (-not $HAS_A) { $EnableArchive = $savedConfig.EnableArchive }
		
		Write-Green "[INFO] Using saved settings:"
		Write-Host "  Playlist URL: $PlaylistUrl"
		Write-Host "  Format: $Format"
		Write-Host "  Quality: $Quality"
		Write-Host "  Delay: ${SleepInterval}s"
		Write-Host "  Archive recovery: $(if ($EnableArchive) { 'ON' } else { 'OFF' })"
		Write-Host ""
	} else {
		Write-Red "ERROR: Playlist URL is required on first run"
		Show-Help
		exit 1
	}
}

if (-not $PlaylistUrl) {
	Write-Red "ERROR: Playlist URL is required"
	Show-Help
	exit 1
}

if ($Quality -notin @('low','mid','high')) {
	Write-Red "ERROR: Quality must be low, mid, or high"
	exit 1
}

if ($SleepInterval -lt 0 -or ($SleepInterval -isnot [int])) {
	Write-Red "ERROR: Sleep interval must be a number"
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
	Write-Yellow "[!] No internet connection detected"
	Write-Yellow "Waiting for connection to resume..."
	while (-not (Test-Internet)) {
		Start-Sleep -Seconds $waitTime
		$elapsed += $waitTime
		if ($elapsed -ge $maxWait) {
			Write-Red "No internet connection after 1 hour. Exiting."
			exit 1
		}
		Write-Blue "  Still waiting... ($elapsed s elapsed)"
	}
	Write-Green "[OK] Internet connection restored! Resuming downloads."
	Start-Sleep -Seconds 5
}

# ========== HELPER FUNCTION TO REMOVE FROM FAILED LOG ==========
function Remove-FromFailedLog {
	param([string]$video_id)
	
	if (-not (Test-Path $FailedLog)) { return }
	
	$content = Get-Content $FailedLog -ErrorAction SilentlyContinue
	if (-not $content) { return }
	
	$newContent = $content | Where-Object { $_ -ne $video_id }
	
	if ($newContent -is [array]) {
		$newContent = $newContent | Where-Object { $_ -ne "" }
	}
	
	if ($newContent -and $newContent.Count -gt 0) {
		$newContent | Set-Content $FailedLog -Force
	} else {
		"" | Set-Content $FailedLog -Force
	}
}

# ========== FORMAT & QUALITY ==========
$AudioFormats = 'mp3','m4a','aac','flac','wav','opus'
$VideoFormats = 'mp4','webm','mkv','avi','mov'
$FormatLower = $Format.ToLower()
if ($AudioFormats -contains $FormatLower) {
	$DownloadType = 'audio'
	$OutputTemplate = '%(uploader)s - %(title)s.%(ext)s'
	Write-Blue "Format: $FormatLower (audio only)"
} elseif ($VideoFormats -contains $FormatLower) {
	$DownloadType = 'video'
	$OutputTemplate = '%(uploader)s - %(title)s.%(ext)s'
	Write-Blue "Format: $FormatLower (video + audio)"
} else {
	Write-Red "ERROR: Unsupported format '$Format'"
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
		Write-Blue "Audio quality: $Quality ($FormatLower)"
	}
	{ $VideoFormats -contains $_ } {
		switch ($Quality) {
			'low'  { $YtdlpArgs = "-f worstvideo+worstaudio --merge-output-format $FormatLower" }
			'mid'  { $YtdlpArgs = "-f bestvideo[height<=480]+bestaudio/best[height<=480] --merge-output-format $FormatLower" }
			'high' { $YtdlpArgs = "-f bestvideo+bestaudio --merge-output-format $FormatLower" }
			default { $YtdlpArgs = "-f bestvideo+bestaudio --merge-output-format $FormatLower" }
		}
		Write-Blue "Video quality: $Quality"
	}
}

# ========== ARCHIVE SEARCH FUNCTIONS ==========
function Extract-Metadata {
	param([string]$html)
	
	$title = ""
	$author = ""
	
	if ($html -match '<title>(.*?)</title>') {
		$title = $matches[1] -replace ' - YouTube', '' -replace ' - GhostArchive', ''
	}
	if (-not $title -and $html -match '<meta property="og:title" content="([^"]+)"') {
		$title = $matches[1]
	}
	if (-not $title -and $html -match '"title":"([^"]+)"') {
		$title = $matches[1] -replace '\\u0026', '&'
	}
	
	if ($html -match '"ownerChannelName":"([^"]+)"') {
		$author = $matches[1]
	}
	if (-not $author -and $html -match '"author":"([^"]+)"') {
		$author = $matches[1]
	}
	if (-not $author -and $html -match '<link itemprop="name" content="([^"]+)"') {
		$author = $matches[1]
	}
	
	$title = $title -replace '^[\s-]+|[\s-]+$', ''
	$author = $author -replace '^[\s-]+|[\s-]+$', ''
	
	return @{ Title = $title; Author = $author }
}

function Search-Archive {
	param([string]$video_id)
	
	Write-Blue "  -> Searching archives for $video_id..."
	
	$ArchiveDir = ".archive_recovered"
	if (-not (Test-Path $ArchiveDir)) { New-Item -ItemType Directory -Path $ArchiveDir | Out-Null }
	
	# Try 1: GhostArchive
	try {
		$ghostUrl = "https://ghostarchive.org/varchive/youtube/$video_id"
		$response = Invoke-WebRequest -Uri $ghostUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction SilentlyContinue
		if ($response.StatusCode -eq 200) {
			Write-Blue "     Found on GhostArchive, downloading..."
			$outputFile = Join-Path $ArchiveDir "%(uploader)s - %(title)s.%(ext)s"
			& $YtDlpExe --no-warnings --no-playlist --output $outputFile $ghostUrl 2>$null
			if ($LASTEXITCODE -eq 0) {
				Write-Green "     Download successful from GhostArchive"
				return $true
			}
		}
	} catch { }
	
	# Try 2: Archive.org direct
	try {
		$archiveUrl = "https://archive.org/details/youtube-$video_id"
		$response = Invoke-WebRequest -Uri $archiveUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction SilentlyContinue
		if ($response.StatusCode -eq 200) {
			Write-Blue "     Found on Archive.org, downloading best format..."
			$outputFile = Join-Path $ArchiveDir "%(uploader)s - %(title)s.%(ext)s"
			& $YtDlpExe --no-warnings --no-playlist -f "bestvideo+bestaudio/best" --output $outputFile $archiveUrl 2>$null
			if ($LASTEXITCODE -eq 0) {
				Write-Green "     Download successful from Archive.org"
				return $true
			}
		}
	} catch { }
	
	# Try 3: Wayback Machine
	try {
		$waybackApi = "https://archive.org/wayback/available?url=https://youtube.com/watch?v=$video_id"
		$response = Invoke-WebRequest -Uri $waybackApi -UseBasicParsing -TimeoutSec 15 -ErrorAction SilentlyContinue
		$content = $response.Content
		
		if ($content -match '"timestamp":"([0-9]+)"') {
			$timestamp = $matches[1]
			Write-Blue "     Found Wayback capture from $timestamp, attempting download..."
			$embedUrl = "https://web.archive.org/web/${timestamp}if_/https://www.youtube.com/embed/$video_id"
			$outputFile = Join-Path $ArchiveDir "%(uploader)s - %(title)s.%(ext)s"
			& $YtDlpExe --no-warnings --no-playlist --output $outputFile $embedUrl 2>$null
			if ($LASTEXITCODE -eq 0) {
				Write-Green "     Download successful from Wayback Machine"
				return $true
			}
		}
	} catch { }
	
	# Try 4: Hobune.stream
	try {
		$hobuneUrl = "https://hobune.stream/yt/${video_id}.mp4"
		$response = Invoke-WebRequest -Uri $hobuneUrl -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
		if ($response.StatusCode -eq 200) {
			Write-Blue "     Found on Hobune.stream, downloading..."
			$outputFile = Join-Path $ArchiveDir "%(uploader)s - %(title)s.%(ext)s"
			& $YtDlpExe --no-warnings --no-playlist --output $outputFile $hobuneUrl 2>$null
			if ($LASTEXITCODE -eq 0) {
				Write-Green "     Download successful from Hobune.stream"
				return $true
			}
		}
	} catch { }
	
	Write-Red "     Not found in any archive"
	return $false
}

# ========== CREATE OUTPUT DIRECTORY ==========
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }

# ========== SAVE CONFIGURATION (if -p was provided) ==========
if ($HAS_P) {
	$configFilePath = Join-Path $OutputDir $ConfigFile
	Save-Config -configPath $configFilePath `
		-playlistUrl $PlaylistUrl `
		-outputDir $OutputDir `
		-sleepInterval $SleepInterval `
		-format $Format `
		-quality $Quality `
		-enableArchive $EnableArchive
}

# ========== CHANGE TO OUTPUT DIRECTORY ==========
Push-Location $OutputDir

# ========== LOG FILES ==========
$DownloadedLog = ".downloaded_ids.txt"
$FailedLog = ".failed_ids.txt"
$PermanentlyFailedLog = ".permanently_failed_ids.txt"
$VideoIdsFile = ".playlist_videos.txt"
$ArchiveDir = ".archive_recovered"
foreach ($file in @($DownloadedLog, $FailedLog, $PermanentlyFailedLog)) { 
	if (-not (Test-Path $file)) { New-Item $file -ItemType File | Out-Null } 
}

# ========== EXTRACT VIDEO IDS ==========
Write-Green "========================================="
Write-Green "Tak Playlist Downloader"
Write-Green "========================================="
Write-Host "Output directory: $OutputDir"
Write-Host "Format: $FormatLower ($DownloadType)"
Write-Host "Quality: $Quality"
Write-Host "Delay: ${SleepInterval}s"
Write-Host "Archive recovery: $(if ($EnableArchive) { 'ON' } else { 'OFF' })"
Write-Host ""

if (-not (Test-Internet)) { Wait-ForInternet }

Write-Blue "Fetching playlist..."
Remove-Item $VideoIdsFile -ErrorAction SilentlyContinue
& $YtDlpExe --cookies-from-browser firefox --flat-playlist --print "%(id)s" $PlaylistUrl | Set-Content $VideoIdsFile
if (-not (Get-Content $VideoIdsFile | Where-Object { $_.Trim() })) {
	& $YtDlpExe --cookies-from-browser firefox --extractor-args youtubetab:skip=authcheck --flat-playlist --print "%(id)s)" $PlaylistUrl | Set-Content $VideoIdsFile
}
if (-not (Get-Content $VideoIdsFile | Where-Object { $_.Trim() })) {
	Write-Red "ERROR: Could not extract video IDs"
	Pop-Location
	exit 1
}

$VideoIds = Get-Content $VideoIdsFile | Where-Object { $_.Trim() }
$Total = $VideoIds.Count

if ($EnableArchive) {
	$DownloadedCount = @(Select-String -Path $DownloadedLog -Pattern "^.*$" | ForEach-Object { $_.Line } | Where-Object { $VideoIds -contains $_ }).Count
	$PermanentlyFailedCount = @(Select-String -Path $PermanentlyFailedLog -Pattern "^.*$" | ForEach-Object { $_.Line } | Where-Object { $VideoIds -contains $_ }).Count
	$Remaining = $Total - $DownloadedCount - $PermanentlyFailedCount
	Write-Host "Total videos: $Total"
	Write-Host "Downloaded (in log): $DownloadedCount"
	Write-Host "Permanently failed: $PermanentlyFailedCount"
	Write-Host "Remaining to process: $Remaining"
	Write-Host "NOTE: With -a enabled, previously failed videos will be checked against archives"
} else {
	$DownloadedCount = @(Select-String -Path $DownloadedLog -Pattern "^.*$" | ForEach-Object { $_.Line } | Where-Object { $VideoIds -contains $_ }).Count
	$PermanentlyFailedCount = @(Select-String -Path $PermanentlyFailedLog -Pattern "^.*$" | ForEach-Object { $_.Line } | Where-Object { $VideoIds -contains $_ }).Count
	$FailedCount = @(Select-String -Path $FailedLog -Pattern "^.*$" | ForEach-Object { $_.Line } | Where-Object { $VideoIds -contains $_ }).Count
	$Remaining = $Total - $DownloadedCount - $PermanentlyFailedCount - $FailedCount
	if ($Remaining -lt 0) { $Remaining = 0 }
	Write-Host "Total videos: $Total"
	Write-Host "Downloaded (in log): $DownloadedCount"
	Write-Host "Permanently failed: $PermanentlyFailedCount"
	Write-Host "Failed (pending retry): $FailedCount"
	Write-Host "Remaining: $Remaining"
}
Write-Host ""

# ========== DOWNLOAD LOOP ==========
$Processed = 0
$YoutubeSuccess = 0
$ArchiveRecovered = 0
$FailedVideos = 0
$PermanentlyFailedThisRun = 0
$SkippedAlready = 0
$SkippedPermanentlyFailed = 0

foreach ($video_id in $VideoIds) {
	$video_id = $video_id.Trim()
	if (-not $video_id) { continue }
	$Processed++
	
	if (Select-String -Path $DownloadedLog -Pattern "^$video_id$" -Quiet) {
		Write-Host "[$($Processed)/$Total] SKIP: $video_id (already downloaded)"
		$SkippedAlready++
		continue
	}
	
	if (Select-String -Path $PermanentlyFailedLog -Pattern "^$video_id$" -Quiet) {
		Write-Host "[$($Processed)/$Total] SKIP: $video_id (permanently failed - not recoverable)"
		$SkippedPermanentlyFailed++
		continue
	}
	
	if (-not $EnableArchive) {
		if (Select-String -Path $FailedLog -Pattern "^$video_id$" -Quiet) {
			Write-Host "[$($Processed)/$Total] SKIP: $video_id (previously failed - will retry later)"
			continue
		}
	}
	
	Write-Host ""
	Write-Yellow "[$($Processed)/$Total] DOWNLOADING: $video_id"
	if (-not (Test-Internet)) { Wait-ForInternet }
	
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
	
	try {
		& $YtDlpExe @args 2>&1 | Out-Null
		$exitCode = $LASTEXITCODE
	} catch {
		$exitCode = 1
	}
	
	if ($exitCode -eq 0) {
		Write-Green "  [OK] Success - added to log"
		Add-Content $DownloadedLog $video_id
		Remove-FromFailedLog -video_id $video_id
		$YoutubeSuccess++
	} else {
		Write-Red "  [X] YouTube failed"
		
		if ($EnableArchive) {
			Write-Blue "  -> Attempting archive recovery..."
			if (Search-Archive -video_id $video_id) {
				Write-Green "  [OK] Recovered from archive!"
				Add-Content $DownloadedLog $video_id
				Remove-FromFailedLog -video_id $video_id
				$ArchiveRecovered++
			} else {
				Write-Red "  [FAILED] Not found in any archive"
				Write-Yellow "  -> Marked as permanently failed (will not retry)"
				Add-Content $PermanentlyFailedLog $video_id
				Remove-FromFailedLog -video_id $video_id
				$PermanentlyFailedThisRun++
			}
		} else {
			Write-Yellow "  -> Archive recovery disabled. Use -a to enable archive search."
			Add-Content $FailedLog $video_id
			$FailedVideos++
		}
	}
	
	if ($SleepInterval -gt 0 -and $Processed -lt $Total) {
		Write-Blue "  Waiting ${SleepInterval}s..."
		Start-Sleep -Seconds $SleepInterval
	}
}

# ========== PROCESS RECOVERED FILES ==========
if ($EnableArchive -and (Test-Path $ArchiveDir)) {
	$recoveredFiles = Get-ChildItem -Path $ArchiveDir -File
	if ($recoveredFiles.Count -gt 0) {
		Write-Host ""
		Write-Blue "Processing recovered files..."
		foreach ($file in $recoveredFiles) {
			$filename = $file.Name
			$extension = $file.Extension.TrimStart('.').ToLower()
			$nameWithoutExt = $file.BaseName
			
			if ($extension -eq $FormatLower) {
				Move-Item -Path $file.FullName -Destination $OutputDir -Force
				Write-Green "  Moved: $filename"
			} elseif ($DownloadType -eq 'audio') {
				$tempFile = Join-Path $OutputDir "$nameWithoutExt.$FormatLower"
				& $FfmpegExe -i $file.FullName -vn -ar 44100 -ac 2 -b:a 192k $tempFile -y 2>$null
				if ($LASTEXITCODE -eq 0) {
					Remove-Item $file.FullName -Force
					Write-Green "  Converted to $FormatLower : $nameWithoutExt.$FormatLower"
				}
			}
		}
		Remove-Item $ArchiveDir -Force -ErrorAction SilentlyContinue
	}
}

# ========== SUMMARY ==========
Write-Host ""
Write-Green "========================================="
Write-Green "COMPLETE!"
Write-Green "========================================="
Write-Host "Total videos: $Total"
Write-Host ""
Write-Green "[OK] Downloaded from YouTube: $YoutubeSuccess"
if ($EnableArchive) {
	Write-Green "[OK] Recovered from archives: $ArchiveRecovered"
}
Write-Blue "- Skipped (already in log): $SkippedAlready"
Write-Blue "- Skipped (permanently failed): $SkippedPermanentlyFailed"
if ($EnableArchive) {
	Write-Red "[FAILED] Permanently failed (not in any archive): $PermanentlyFailedThisRun"
} else {
	Write-Red "[FAILED] Newly failed: $FailedVideos"
}
Write-Host ""
Write-Host "Files saved to: $OutputDir"
Write-Host ""

if ($EnableArchive) {
	Write-Host "Permanently failed videos saved to: $PermanentlyFailedLog"
	Write-Host "These videos were not found on YouTube or any archive and will NOT be retried."
} else {
	Write-Host "Failed videos saved to: $FailedLog"
	Write-Host "Run Retry-Failed.ps1 later to retry them"
}

# ========== RESTORE ORIGINAL LOCATION ==========
Pop-Location