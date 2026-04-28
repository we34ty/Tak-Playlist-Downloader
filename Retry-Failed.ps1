# ========== ARGUMENT PARSING ========== 
param(
	[string]$o,
	[int]$t,
	[string]$f,
	[string]$q,
	[switch]$h
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

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

# ========== DEFAULT CONFIGURATION ==========
$OutputDir = Get-Location
$SleepInterval = 11
$Format = 'mp3'
$Quality = 'mid'
$TakDataDir = ".TakData"

# ========== COLOR FUNCTIONS ========== 
function Write-Red { Write-Host $args -ForegroundColor Red }
function Write-Green { Write-Host $args -ForegroundColor Green }
function Write-Yellow { Write-Host $args -ForegroundColor Yellow }
function Write-Blue { Write-Host $args -ForegroundColor Blue }
function Write-Cyan { Write-Host $args -ForegroundColor Cyan }
function Write-Magenta { Write-Host $args -ForegroundColor Magenta }

function Show-Help {
	Write-Host "Usage: .\Retry-Failed.ps1 [-o <OUTPUT_DIR>] [-t <SECONDS>] [-f <FORMAT>] [-q <QUALITY>] [-h]" -ForegroundColor Cyan
	Write-Host ""
	Write-Host "Options:"
	Write-Host "  -o <DIR>        Output directory (default: current directory)"
	Write-Host "  -t <SECONDS>    Sleep interval between retries (default: 11)"
	Write-Host "  -f <FORMAT>     Output format (default: mp3)"
	Write-Host "  -q <QUALITY>    Quality: low, mid, high (default: mid)"
	Write-Host "  -h             Show this help message"
	Write-Host ""
	Write-Host "Note: Settings and logs are stored in '$TakDataDir' subfolder"
}

# ========== FUNCTION TO GET TAKDATA PATH ==========
function Get-TakDataPath {
	param([string]$outputDir)
	$takDataPath = Join-Path $outputDir $TakDataDir
	if (-not (Test-Path $takDataPath)) {
		New-Item -ItemType Directory -Path $takDataPath -Force | Out-Null
	}
	return $takDataPath
}

# ========== TRACK WHICH ARGUMENTS WERE PROVIDED ==========
$HAS_O = $PSBoundParameters.ContainsKey('o')
$HAS_T = $PSBoundParameters.ContainsKey('t')
$HAS_F = $PSBoundParameters.ContainsKey('f')
$HAS_Q = $PSBoundParameters.ContainsKey('q')
$HAS_H = $PSBoundParameters.ContainsKey('h')

if ($HAS_H) { Show-Help; exit 0 }

if ($HAS_O) { $OutputDir = $o }
if ($HAS_T) { $SleepInterval = $t }
if ($HAS_F) { $Format = $f }
if ($HAS_Q) { $Quality = $q }

# Normalize path
$OutputDir = $OutputDir -replace '/', '\'

# ========== GET TAKDATA PATH ==========
$TakDataPath = Get-TakDataPath -outputDir $OutputDir
$ConfigFile = Join-Path $TakDataPath "download_config.json"

# ========== LOAD SAVED CONFIGURATION ==========
$savedConfig = $null
if (Test-Path $ConfigFile) {
	try {
		$savedConfig = Get-Content $ConfigFile -Raw | ConvertFrom-Json
		Write-Blue "Loading saved configuration from: $ConfigFile"
		
		if (-not $HAS_O) { $OutputDir = $savedConfig.OutputDir }
		if (-not $HAS_T) { $SleepInterval = $savedConfig.SleepInterval }
		if (-not $HAS_F) { $Format = $savedConfig.Format }
		if (-not $HAS_Q) { $Quality = $savedConfig.Quality }
		
		Write-Green "[INFO] Using saved settings from: $ConfigFile"
		Write-Host "  Format: $Format"
		Write-Host "  Quality: $Quality"
		Write-Host "  Delay: ${SleepInterval}s"
		Write-Host ""
	} catch {
		Write-Yellow "Could not parse saved configuration, using defaults"
	}
}

# Validate values
if ($Quality -notin @('low','mid','high')) {
	Write-Red "ERROR: Quality must be low, mid, or high"
	exit 1
}

if ($SleepInterval -lt 0 -or ($SleepInterval -isnot [int])) {
	Write-Red "ERROR: Sleep interval must be a number"
	exit 1
}

# ========== SAVE CONFIGURATION IF CHANGED ==========
if ($HAS_F -or $HAS_Q -or $HAS_T) {
	$existingConfig = $null
	if (Test-Path $ConfigFile) {
		$existingConfig = Get-Content $ConfigFile -Raw | ConvertFrom-Json
	}
	
	$config = @{
		PlaylistUrl = if ($existingConfig) { $existingConfig.PlaylistUrl } else { "" }
		OutputDir = $OutputDir
		SleepInterval = $SleepInterval
		Format = $Format
		Quality = $Quality
		EnableArchive = if ($existingConfig) { $existingConfig.EnableArchive } else { $false }
		LastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
	}
	
	$config | ConvertTo-Json | Set-Content $ConfigFile
	Write-Blue "Configuration updated in: $ConfigFile"
}

# ========== VALIDATE FORMAT ==========
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

# ========== SET QUALITY PARAMETERS ==========
switch ($FormatLower) {
	{ $AudioFormats -contains $_ } {
		switch ($Quality) {
			'low'  { $YtdlpArgs = "-f bestaudio -x --audio-format $FormatLower --audio-quality 5" }
			'mid'  { $YtdlpArgs = "-f bestaudio -x --audio-format $FormatLower --audio-quality 2" }
			'high' { $YtdlpArgs = "-f bestaudio -x --audio-format $FormatLower --audio-quality 0" }
			default { $YtdlpArgs = "-f bestaudio -x --audio-format $FormatLower --audio-quality 2" }
		}
	}
	{ $VideoFormats -contains $_ } {
		switch ($Quality) {
			'low'  { $YtdlpArgs = "-f worstvideo+worstaudio --merge-output-format $FormatLower" }
			'mid'  { $YtdlpArgs = "-f bestvideo[height<=480]+bestaudio/best[height<=480] --merge-output-format $FormatLower" }
			'high' { $YtdlpArgs = "-f bestvideo+bestaudio --merge-output-format $FormatLower" }
			default { $YtdlpArgs = "-f bestvideo+bestaudio --merge-output-format $FormatLower" }
		}
	}
}
Write-Blue "Quality: $Quality (forcing ${FormatLower} conversion)"

# ========== INTERNET FUNCTIONS ==========
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
	$elapsed = 0
	Write-Yellow "No internet connection detected"
	Write-Yellow "Waiting for connection to resume..."
	while (-not (Test-Internet)) {
		Start-Sleep -Seconds $waitTime
		$elapsed += $waitTime
		Write-Blue "  Still waiting... ($elapsed s elapsed)"
	}
	Write-Green "Internet connection restored! Resuming."
	Start-Sleep -Seconds 5
}

# ========== HELPER FUNCTION ==========
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

# ========== CREATE OUTPUT DIRECTORY ==========
if (-not (Test-Path $OutputDir)) {
	Write-Yellow "Directory does not exist, creating: $OutputDir"
	New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# ========== CHANGE TO OUTPUT DIRECTORY ==========
Push-Location $OutputDir

# ========== SET UP LOG FILES IN TAKDATA ==========
$TakDataPath = Get-TakDataPath -outputDir $OutputDir
$DownloadedLog = Join-Path $TakDataPath "downloaded_ids.txt"
$FailedLog = Join-Path $TakDataPath "failed_ids.txt"
$PermanentlyFailedLog = Join-Path $TakDataPath "permanently_failed_ids.txt"
$RecoveredLog = Join-Path $TakDataPath "recovered_ids.txt"
$ArchiveDir = Join-Path $TakDataPath "archive_recovered"

foreach ($file in @($DownloadedLog, $FailedLog, $PermanentlyFailedLog, $RecoveredLog)) { 
	if (-not (Test-Path $file)) { New-Item $file -ItemType File | Out-Null } 
}
if (-not (Test-Path $ArchiveDir)) { New-Item -ItemType Directory -Path $ArchiveDir | Out-Null }

Write-Blue "TakData directory: $TakDataPath"
Write-Blue "Log files stored in TakData subfolder"

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

# ========== MAIN RETRY LOOP ==========
Write-Green "========================================="
Write-Green "Retry Failed Downloads with Archive Search"
Write-Green "========================================="
Write-Host "Output directory: $OutputDir"
Write-Host "TakData directory: $TakDataPath"
Write-Host "Format: $FormatLower ($DownloadType)"
Write-Host "Quality: $Quality"
Write-Host "Delay between retries: ${SleepInterval}s"
Write-Host ""

if (-not (Test-Path $FailedLog) -or (Get-Content $FailedLog | Where-Object { $_.Trim() } | Measure-Object).Count -eq 0) {
	Write-Yellow "No failed_ids.txt found or it's empty. Nothing to retry."
	Pop-Location
	exit 1
}

if (-not (Test-Internet)) { Wait-ForInternet }

# Filter out already downloaded or permanently failed videos
$RetryList = @()
$PermanentlyFailedCount = 0
foreach ($video_id in Get-Content $FailedLog | Where-Object { $_.Trim() }) {
	if (Select-String -Path $DownloadedLog -Pattern "^$video_id$" -Quiet) { continue }
	if (Select-String -Path $PermanentlyFailedLog -Pattern "^$video_id$" -Quiet) { 
		$PermanentlyFailedCount++
		continue 
	}
	if (Select-String -Path $RecoveredLog -Pattern "^$video_id$" -Quiet) { continue }
	$RetryList += $video_id
}

$Total = $RetryList.Count
if ($Total -eq 0) {
	if ($PermanentlyFailedCount -gt 0) {
		Write-Green "All failed videos have been downloaded or marked permanently failed!"
		Write-Yellow "Skipped $PermanentlyFailedCount permanently failed videos"
	} else {
		Write-Green "All failed videos have been downloaded or recovered!"
	}
	Pop-Location
	exit 0
}

Write-Cyan "Videos to retry: $Total"
if ($PermanentlyFailedCount -gt 0) {
	Write-Yellow "Permanently failed (skipped): $PermanentlyFailedCount"
}
Write-Host ""

$Current = 0
$Success = 0
$Recovered = 0
$PermanentlyFailed = 0

foreach ($video_id in $RetryList) {
	$Current++
	Write-Host ""
	Write-Yellow "[$Current/$Total] RETRYING: $video_id"
	
	if (-not (Test-Internet)) { Wait-ForInternet }
	
	# First try YouTube
	Write-Blue "  -> Trying YouTube..."
	
	$ytDlpArgsArr = @(
		'--cookies-from-browser', 'firefox',
		'--extractor-args', 'youtubetab:skip=authcheck'
	)
	$ytDlpArgsArr += $YtdlpArgs -split ' '
	$ytDlpArgsArr += '--embed-thumbnail', '--add-metadata', '--output', $OutputTemplate, '--no-overwrites', '--continue', "https://youtube.com/watch?v=$video_id"
	
	try {
		& $YtDlpExe @ytDlpArgsArr 2>&1 | Out-Null
		$exitCode = $LASTEXITCODE
	} catch {
		$exitCode = 1
	}
	
	if ($exitCode -eq 0) {
		Write-Green "  Downloaded successfully from YouTube"
		Add-Content $DownloadedLog $video_id
		Remove-FromFailedLog -video_id $video_id
		$Success++
	} else {
		Write-Red "  Still unavailable on YouTube"
		
		# Try archive recovery
		Write-Blue "  -> Attempting archive recovery..."
		if (Search-Archive -video_id $video_id) {
			Write-Green "  Recovered from archive!"
			Add-Content $DownloadedLog $video_id
			Remove-FromFailedLog -video_id $video_id
			$Recovered++
		} else {
			Write-Red "  Not found in any archive"
			Write-Yellow "  -> Marked as permanently failed"
			Add-Content $PermanentlyFailedLog $video_id
			Remove-FromFailedLog -video_id $video_id
			$PermanentlyFailed++
		}
	}
	
	if ($Current -lt $Total) {
		Write-Blue "  Waiting ${SleepInterval}s..."
		Start-Sleep -Seconds $SleepInterval
	}
}

# ========== PROCESS RECOVERED FILES ==========
if (Test-Path $ArchiveDir) {
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
Write-Green "RETRY COMPLETE"
Write-Green "========================================="
Write-Green "Downloaded from YouTube: $Success"
Write-Green "Recovered from archives: $Recovered"
Write-Yellow "Permanently failed: $PermanentlyFailed"
Write-Host ""
Write-Host "Files saved to: $OutputDir"
Write-Host "Settings and logs saved to: $TakDataPath"
Write-Host ""
Write-Host "Downloaded log: $DownloadedLog"
Write-Host "Failed log: $FailedLog"
Write-Host "Permanently failed log: $PermanentlyFailedLog"
if ($PermanentlyFailed -gt 0) {
	Write-Host ""
	Write-Yellow "Videos marked as permanently failed will NOT be retried again."
	Write-Yellow "To retry them anyway, remove their IDs from $PermanentlyFailedLog"
}

# ========== RESTORE ORIGINAL LOCATION ==========
Pop-Location