
# ========== ARGUMENT PARSING (MUST BE FIRST) ========== 
param(
	[string]$o,
	[int]$t,
	[string]$f,
	[string]$q,
	[switch]$h
)

# ========== DEFAULT CONFIGURATION ========== 
$OutputDir = Get-Location
$SleepInterval = 11
$Format = 'mp3'
$Quality = 'mid'

# ========== COLOR CONSTANTS (Write-Host Wrappers) ========== 
$Red     = { param($msg) Write-Host $msg -ForegroundColor Red }
$Green   = { param($msg) Write-Host $msg -ForegroundColor Green }
$Yellow  = { param($msg) Write-Host $msg -ForegroundColor Yellow }
$Blue    = { param($msg) Write-Host $msg -ForegroundColor Blue }
$Cyan    = { param($msg) Write-Host $msg -ForegroundColor Cyan }

function Show-Help {
	Write-Host "Usage: .\Retry-Failed.ps1 [-o <OUTPUT_DIR>] [-t <SECONDS>] [-f <FORMAT>] [-q <QUALITY>] [-h]" -ForegroundColor Cyan
	Write-Host ""
	Write-Host "Options:"
	Write-Host "  -o <DIR>        Output directory (default: current directory)"
	Write-Host "  -t <SECONDS>    Sleep interval between retries (default: 11)"
	Write-Host "  -f <FORMAT>     Output format (default: mp3)"
	Write-Host "  -q <QUALITY>    Quality: low, mid, high (default: mid)"
	Write-Host "  -h             Show this help message"
}

if ($h) { Show-Help; exit 0 }
if ($o) { $OutputDir = $o }
if ($t) { $SleepInterval = $t }
if ($f) { $Format = $f }
if ($q) { $Quality = $q }

if ($Quality -and $Quality -notin @('low','mid','high')) {
	& $Red "ERROR: Quality must be low, mid, or high"
	exit 1
}

if ($SleepInterval -lt 0 -or ($SleepInterval -isnot [int])) {
	& $Red "ERROR: Sleep interval must be a number"
	exit 1
}

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
	& $Yellow "No internet connection detected"
	& $Yellow "Waiting for connection to resume..."
	while (-not (Test-Internet)) {
		Start-Sleep -Seconds $waitTime
		$elapsed += $waitTime
		& $Blue "  Still waiting... ($elapsed s elapsed)"
	}
	& $Green "Internet connection restored! Resuming."
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

# ========== CHANGE TO OUTPUT DIRECTORY ==========
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
Set-Location $OutputDir

# ========== LOG FILES ==========
$DownloadedLog = ".downloaded_ids.txt"
$FailedLog = ".failed_ids.txt"
$PermanentlyFailedLog = ".permanently_failed_ids.txt"
foreach ($file in @($DownloadedLog, $FailedLog, $PermanentlyFailedLog)) { if (-not (Test-Path $file)) { New-Item $file -ItemType File | Out-Null } }

# ========== MAIN RETRY LOOP ==========
& $Green "========================================="
& $Green "Retry Failed Downloads"
& $Green "========================================="
Write-Host "Output directory: $OutputDir"
Write-Host "Format: $FormatLower ($DownloadType)"
Write-Host "Quality: $Quality"
Write-Host "Delay between retries: ${SleepInterval}s"
Write-Host ""

if (-not (Test-Path $FailedLog) -or -not (Get-Content $FailedLog | Where-Object { $_.Trim() })) {
	& $Yellow "No .failed_ids.txt found or it's empty. Nothing to retry."
	exit 1
}

if (-not (Test-Internet)) { Wait-ForInternet }

# Filter out permanently failed and already downloaded
$RetryList = @()
foreach ($video_id in Get-Content $FailedLog | Where-Object { $_.Trim() }) {
	if (Select-String -Path $PermanentlyFailedLog -Pattern "^$video_id$" -Quiet) { continue }
	if (Select-String -Path $DownloadedLog -Pattern "^$video_id$" -Quiet) { continue }
	$RetryList += $video_id
}
$Total = $RetryList.Count
if ($Total -eq 0) {
	& $Green "All failed videos have been recovered or marked permanently failed!"
	exit 0
}

& $Cyan "Videos to retry: $Total"
Write-Host ""

$Current = 0
$Success = 0
$StillFailed = 0

foreach ($video_id in $RetryList) {
	$Current++
	Write-Host ""
	& $Yellow "[$Current/$Total] RETRYING: $video_id"
	if (-not (Test-Internet)) { Wait-ForInternet }
	& $Blue "  -> Trying YouTube..."
	$ytDlpArgsArr = @(
		'--cookies-from-browser', 'firefox',
		'--extractor-args', 'youtubetab:skip=authcheck'
	)
	$ytDlpArgsArr += $YtdlpArgs -split ' '
	$ytDlpArgsArr += '--embed-thumbnail', '--add-metadata', '--output', $OutputTemplate, '--no-overwrites', '--continue', "https://youtube.com/watch?v=$video_id"
	& $YtDlpExe @ytDlpArgsArr
	if ($LASTEXITCODE -eq 0) {
		& $Green "  Downloaded successfully"
		Add-Content $DownloadedLog $video_id
		# Remove from failed
		(Get-Content $FailedLog | Where-Object { $_ -ne $video_id }) | Set-Content $FailedLog
		$Success++
	} else {
		& $Red "  Still unavailable on YouTube"
		& $Yellow "  -> Marked as permanently failed"
		Add-Content $PermanentlyFailedLog $video_id
		(Get-Content $FailedLog | Where-Object { $_ -ne $video_id }) | Set-Content $FailedLog
		$StillFailed++
	}
	if ($Current -lt $Total) {
		& $Blue "  Waiting ${SleepInterval}s..."
		Start-Sleep -Seconds $SleepInterval
	}
}

# ========== SUMMARY ==========
Write-Host ""
& $Green "========================================="
& $Green "RETRY COMPLETE"
& $Green "========================================="
& $Green "Downloaded from YouTube: $Success"
& $Red "Permanently failed: $StillFailed"
Write-Host ""
Write-Host "Permanently failed videos saved to: $PermanentlyFailedLog"
