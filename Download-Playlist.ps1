$MaxWaitSeconds = 3600  # 1 hour
$WaitInterval = 30

function Test-Internet {
    try {
        $null = Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 3
        return $true
    } catch {
        return $false
    }
}

function Wait-ForInternet {
    $elapsed = 0
    Write-Host "⚠️  No internet connection detected"
    Write-Host "Waiting for connection to resume..."
    while (-not (Test-Internet)) {
        Start-Sleep -Seconds $WaitInterval
        $elapsed += $WaitInterval
        if ($elapsed -ge $MaxWaitSeconds) {
            Write-Host "No internet connection after 1 hour. Exiting."
            exit 1
        }
        Write-Host "  Still waiting... ($elapsed s elapsed)"
    }
    Write-Host "✓ Internet connection restored! Resuming downloads."
    Start-Sleep -Seconds 5
}
# Tak YouTube Playlist Downloader (PowerShell)
# Windows version: Archive recovery is NOT supported

param(
    [string]$PlaylistUrl,
    [string]$OutputDir = (Get-Location).Path,
    [int]$SleepInterval = 11,
    [string]$Format = "mp3"
)

function Show-Help {
    Write-Host "Usage: .\Download-Playlist.ps1 -PlaylistUrl <URL> [-OutputDir <DIR>] [-SleepInterval <SECONDS>] [-Format <mp3|mp4|flac|etc>]"
    Write-Host "\nRequired:"
    Write-Host "  -PlaylistUrl   YouTube playlist URL"
    Write-Host "\nOptions:"
    Write-Host "  -OutputDir     Output directory (default: current directory)"
    Write-Host "  -SleepInterval Sleep between downloads (default: 11)"
    Write-Host "  -Format        Output format (mp3, mp4, flac, etc.) (default: mp3)"
    Write-Host "\nNote: Archive recovery is NOT available in Windows version."
}

if (-not $PlaylistUrl) {
    Show-Help
    exit 1
}

$LogFile = Join-Path $OutputDir 'downloaded_ids.txt'
$FailedLog = Join-Path $OutputDir 'failed_ids.txt'
$RecoveredLog = Join-Path $OutputDir 'recovered_ids.txt'
$PermFailedLog = Join-Path $OutputDir 'permanently_failed_ids.txt'
$VideoIdsFile = Join-Path $OutputDir 'playlist_videos.txt'

if (!(Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
Set-Location $OutputDir


# Check internet before starting
if (-not (Test-Internet)) { Wait-ForInternet }

# Extract video IDs
Write-Host "Fetching playlist..."
$ytDlpCmd = "yt-dlp --flat-playlist --print `"%(id)s`" `"$PlaylistUrl`" > `"$VideoIdsFile`""
Invoke-Expression $ytDlpCmd

if (!(Test-Path $VideoIdsFile) -or !(Get-Content $VideoIdsFile)) {
    Write-Host "ERROR: Could not extract video IDs"
    exit 1
}

$VideoIds = Get-Content $VideoIdsFile | Where-Object { $_.Trim() -ne "" }
$Total = $VideoIds.Count
$Downloaded = @()
if (Test-Path $LogFile) { $Downloaded = Get-Content $LogFile }
$Recovered = @()
if (Test-Path $RecoveredLog) { $Recovered = Get-Content $RecoveredLog }
$PermFailed = @()
if (Test-Path $PermFailedLog) { $PermFailed = Get-Content $PermFailedLog }

$Processed = 0
foreach ($videoId in $VideoIds) {
    $Processed++
    if ($PermFailed -contains $videoId) {
        Write-Host "[$Processed/$Total] SKIP: $videoId (permanently unavailable)"
        continue
    }
    if ($Downloaded -contains $videoId -or $Recovered -contains $videoId) {
        Write-Host "[$Processed/$Total] SKIP: $videoId (already have)"
        continue
    }
    Write-Host "[$Processed/$Total] DOWNLOADING: $videoId"

    # Check internet before each download
    if (-not (Test-Internet)) { Wait-ForInternet }

    $ytDlpArgs = if ($Format -in @('mp3','m4a','aac','flac','wav','opus')) {
        "-f ba -x --audio-format $Format"
    } else {
        "-f bestvideo+bestaudio --merge-output-format $Format"
    }
    $outputTemplate = '%(uploader)s - %(title)s.%(ext)s'
    $cmd = "yt-dlp $ytDlpArgs --embed-thumbnail --add-metadata --output `"$outputTemplate`" --no-overwrites --continue --no-warnings https://youtube.com/watch?v=$videoId"
    if (Invoke-Expression $cmd) {
        Add-Content $LogFile $videoId
        Write-Host "  ✓ Success"
    } else {
        Add-Content $FailedLog $videoId
        Write-Host "  ✗ Failed"
    }
    if ($SleepInterval -gt 0 -and $Processed -lt $Total) {
        Start-Sleep -Seconds $SleepInterval
    }
}
Write-Host "\nCOMPLETE! Files saved to: $OutputDir"
Write-Host "Note: Archive recovery is not available in this version."
