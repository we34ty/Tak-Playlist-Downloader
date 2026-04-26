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
# Tak Retry Failed Downloads (PowerShell)
# Windows version: Archive recovery is NOT supported

param(
    [string]$OutputDir = (Get-Location).Path,
    [int]$SleepInterval = 11,
    [string]$Format = "mp3"
)

function Show-Help {
    Write-Host "Usage: .\Retry-Failed.ps1 [-OutputDir <DIR>] [-SleepInterval <SECONDS>] [-Format <mp3|mp4|flac|etc>]"
    Write-Host "\nOptions:"
    Write-Host "  -OutputDir     Output directory (default: current directory)"
    Write-Host "  -SleepInterval Sleep between retries (default: 11)"
    Write-Host "  -Format        Output format (mp3, mp4, flac, etc.) (default: mp3)"
    Write-Host "\nNote: Archive recovery is NOT available in Windows version."
}

$FailedLog = Join-Path $OutputDir 'failed_ids.txt'
$LogFile = Join-Path $OutputDir 'downloaded_ids.txt'
$RecoveredLog = Join-Path $OutputDir 'recovered_ids.txt'
$PermFailedLog = Join-Path $OutputDir 'permanently_failed_ids.txt'

if (!(Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
Set-Location $OutputDir


# Check internet before starting
if (-not (Test-Internet)) { Wait-ForInternet }

if (!(Test-Path $FailedLog) -or !(Get-Content $FailedLog)) {
    Write-Host "No failed_ids.txt found or it's empty. Nothing to retry."
    exit 1
}

$FailedIds = Get-Content $FailedLog | Where-Object { $_.Trim() -ne "" }
$Downloaded = @()
if (Test-Path $LogFile) { $Downloaded = Get-Content $LogFile }
$Recovered = @()
if (Test-Path $RecoveredLog) { $Recovered = Get-Content $RecoveredLog }
$PermFailed = @()
if (Test-Path $PermFailedLog) { $PermFailed = Get-Content $PermFailedLog }

$RetryList = $FailedIds | Where-Object { ($Downloaded -notcontains $_) -and ($Recovered -notcontains $_) -and ($PermFailed -notcontains $_) }
$Total = $RetryList.Count
if ($Total -eq 0) {
    Write-Host "All failed videos have been recovered or marked permanently failed!"
    exit 0
}

$Processed = 0
foreach ($videoId in $RetryList) {
    $Processed++
    Write-Host "[$Processed/$Total] RETRYING: $videoId"

    # Check internet before each retry
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
        Write-Host "  ✓ Downloaded successfully"
    } else {
        Add-Content $PermFailedLog $videoId
        Write-Host "  ✗ Still unavailable. Marked as permanently failed."
    }
    if ($SleepInterval -gt 0 -and $Processed -lt $Total) {
        Start-Sleep -Seconds $SleepInterval
    }
}
Write-Host "\nRETRY COMPLETE! Files saved to: $OutputDir"
Write-Host "Note: Archive recovery is not available in this version."
