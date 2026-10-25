param(
	[string]$o,
	[int]$t,
	[string]$f,
	[string]$q,
	[string]$b,
	[switch]$h
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Browser = "firefox"

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

$OutputDir = Get-Location
$SleepInterval = 11
$Format = 'mp3'
$Quality = 'mid'
$TakDataDir = ".TakData"

function Write-Red { Write-Host $args -ForegroundColor Red }
function Write-Green { Write-Host $args -ForegroundColor Green }
function Write-Yellow { Write-Host $args -ForegroundColor Yellow }
function Write-Blue { Write-Host $args -ForegroundColor Blue }
function Write-Cyan { Write-Host $args -ForegroundColor Cyan }
function Write-Magenta { Write-Host $args -ForegroundColor Magenta }

function Show-Help {
	Write-Host "Usage: .\Retry-Failed.ps1 [-o <OUTPUT_DIR>] [-t <SECONDS>] [-f <FORMAT>] [-q <QUALITY>] [-b <BROWSER>] [-h]" -ForegroundColor Cyan
	Write-Host ""
	Write-Host "Options:"
	Write-Host "  -o <DIR>        Output directory (default: current directory)"
	Write-Host "  -t <SECONDS>    Sleep interval between retries (default: 11)"
	Write-Host "  -f <FORMAT>     Output format (default: mp3)"
	Write-Host "  -q <QUALITY>    Quality: low, mid, high (default: mid)"
	Write-Host "  -b <BROWSER>    Browser for cookies: firefox, chrome, chromium, brave, edge, opera, vivaldi, safari, none (default: firefox)"
	Write-Host "  -h             Show this help message"
	Write-Host ""
	Write-Host "Note: Settings and logs are stored in '$TakDataDir' subfolder"
}

function Get-TakDataPath {
	param([string]$outputDir)
	$takDataPath = Join-Path $outputDir $TakDataDir
	if (-not (Test-Path $takDataPath)) {
		New-Item -ItemType Directory -Path $takDataPath -Force | Out-Null
	}
	return $takDataPath
}

$HAS_O = $PSBoundParameters.ContainsKey('o')
$HAS_T = $PSBoundParameters.ContainsKey('t')
$HAS_F = $PSBoundParameters.ContainsKey('f')
$HAS_Q = $PSBoundParameters.ContainsKey('q')
$HAS_B = $PSBoundParameters.ContainsKey('b')
$HAS_H = $PSBoundParameters.ContainsKey('h')

if ($HAS_H) { Show-Help; exit 0 }

if ($HAS_O) { $OutputDir = $o }
if ($HAS_T) { $SleepInterval = $t }
if ($HAS_F) { $Format = $f }
if ($HAS_Q) { $Quality = $q }
if ($HAS_B) { $Browser = $b }

$OutputDir = $OutputDir -replace '/', '\'

$TakDataPath = Get-TakDataPath -outputDir $OutputDir
$ConfigFile = Join-Path $TakDataPath "download_config.json"

$savedConfig = $null
if (Test-Path $ConfigFile) {
	try {
		$savedConfig = Get-Content $ConfigFile -Raw | ConvertFrom-Json
		Write-Blue "Loading saved configuration from: $ConfigFile"
		if (-not $HAS_O) { $OutputDir = $savedConfig.OutputDir }
		if (-not $HAS_T) { $SleepInterval = $savedConfig.SleepInterval }
		if (-not $HAS_F) { $Format = $savedConfig.Format }
		if (-not $HAS_Q) { $Quality = $savedConfig.Quality }
		if (-not $HAS_B) { $Browser = $savedConfig.Browser }
		Write-Green "[INFO] Using saved settings from: $ConfigFile"
		Write-Host "  Format: $Format"
		Write-Host "  Quality: $Quality"
		Write-Host "  Browser: $Browser"
		Write-Host "  Delay: ${SleepInterval}s"
		Write-Host ""
	} catch {
		Write-Yellow "Could not parse saved configuration, using defaults"
	}
}

if ($Quality -notin @('low','mid','high')) {
	Write-Red "ERROR: Quality must be low, mid, or high"
	exit 1
}

if ($SleepInterval -lt 0 -or ($SleepInterval -isnot [int])) {
	Write-Red "ERROR: Sleep interval must be a number"
	exit 1
}

if ($HAS_F -or $HAS_Q -or $HAS_T -or $HAS_B) {
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
		Browser = $Browser
		EnableArchive = if ($existingConfig) { $existingConfig.EnableArchive } else { $false }
		LastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
	}
	$config | ConvertTo-Json | Set-Content $ConfigFile
	Write-Blue "Configuration updated in: $ConfigFile"
}

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

if (-not (Test-Path $OutputDir)) {
	Write-Yellow "Directory does not exist, creating: $OutputDir"
	New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Push-Location $OutputDir

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

# ========== ARCHIVE SEARCH VIA AGGREGATOR API ==========
function Search-Archive {
	param([string]$video_id)
	
	$apiUrl = "https://findyoutubevideo.thetechrobo.ca/api/v5/$video_id"
	Write-Blue "  -> Querying archive aggregator for $video_id..."
	
	try {
		$response = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 30 -ErrorAction SilentlyContinue
	} catch {
		Write-Red "     ✗ Failed to query aggregator API"
		return $false
	}
	
	if ($null -eq $response) {
		Write-Red "     ✗ No response from aggregator API"
		return $false
	}
	
	if ($response.status -eq "bad.id") {
		Write-Red "     ✗ Invalid video ID"
		return $false
	}
	
	$videoFound = $false
	if ($response.verdict -and $response.verdict.video -eq $true) {
		$videoFound = $true
	}
	
	if (-not $videoFound) {
		Write-Yellow "     ✗ No full video found in any archive"
		return $false
	}
	
	Write-Green "     ✓ Video found in archives!"
	
	$downloadUrl = $null
	if ($response.keys) {
		foreach ($key in $response.keys) {
			if ($key.archived -eq $true -and $key.available) {
				foreach ($avail in $key.available) {
					if ($avail.url) {
						$downloadUrl = $avail.url
						break
					}
				}
			}
			if ($downloadUrl) { break }
		}
	}
	
	if (-not $downloadUrl) {
		Write-Red "     ✗ Found verdict but no direct download URL"
		return $false
	}
	
	Write-Blue "     → Downloading from archive..."
	$outputFile = Join-Path $ArchiveDir "%(uploader)s - %(title)s.%(ext)s"
	& $YtDlpExe --no-warnings --no-playlist --output $outputFile $downloadUrl 2>$null
	if ($LASTEXITCODE -eq 0) {
		Write-Green "     Download successful from archive"
		return $true
	}
	
	Write-Red "     ✗ Download from archive failed"
	return $false
}

Write-Green "========================================="
Write-Green "Retry Failed Downloads with Archive Search"
Write-Green "========================================="
Write-Host "Output directory: $OutputDir"
Write-Host "TakData directory: $TakDataPath"
Write-Host "Format: $FormatLower ($DownloadType)"
Write-Host "Quality: $Quality"
Write-Host "Browser: $Browser"
Write-Host "Delay between retries: ${SleepInterval}s"
Write-Host ""

if (-not (Test-Path $FailedLog) -or (Get-Content $FailedLog | Where-Object { $_.Trim() } | Measure-Object).Count -eq 0) {
	Write-Yellow "No failed_ids.txt found or it's empty. Nothing to retry."
	Pop-Location
	exit 1
}

if (-not (Test-Internet)) { Wait-ForInternet }

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
	
	Write-Blue "  -> Trying YouTube..."
	
	$ytDlpArgsArr = @()
	if ($Browser -ne "none") {
		$ytDlpArgsArr += '--cookies-from-browser'; $ytDlpArgsArr += $Browser
	}
	$ytDlpArgsArr += '--extractor-args'; $ytDlpArgsArr += 'youtubetab:skip=authcheck'
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

Pop-Location