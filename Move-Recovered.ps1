# ========== ARGUMENT PARSING ==========
param(
	[string]$o,
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
$Format = 'mp3'
$Quality = 'mid'
$ConfigFile = ".download_config.txt"

# ========== COLOR FUNCTIONS ========== 
function Write-Red { Write-Host $args -ForegroundColor Red }
function Write-Green { Write-Host $args -ForegroundColor Green }
function Write-Yellow { Write-Host $args -ForegroundColor Yellow }
function Write-Blue { Write-Host $args -ForegroundColor Blue }
function Write-Cyan { Write-Host $args -ForegroundColor Cyan }
function Write-Magenta { Write-Host $args -ForegroundColor Magenta }

function Show-Help {
	Write-Host "Usage: .\Move-Recovered.ps1 [-o <OUTPUT_DIR>] [-f <FORMAT>] [-q <QUALITY>] [-h]" -ForegroundColor Cyan
	Write-Host ""
	Write-Host "Options:"
	Write-Host "  -o <DIR>        Output directory (default: current directory)"
	Write-Host "  -f <FORMAT>     Target format for conversion (default: mp3)"
	Write-Host "                Audio: mp3, m4a, aac, flac, wav, opus"
	Write-Host "                Video: mp4, webm, mkv, avi, mov"
	Write-Host "  -q <QUALITY>    Quality: low, mid, high (default: mid)"
	Write-Host "  -h             Show this help message"
	Write-Host ""
	Write-Host "Note: This script shares configuration with Download-Playlist.ps1"
	Write-Host "      Settings from .download_config.txt will be used if present."
}

# ========== PARSE ARGUMENTS AND TRACK WHAT WAS PROVIDED ==========
$HAS_O = $false
$HAS_F = $false
$HAS_Q = $false

for ($i = 0; $i -lt $args.Length; $i++) {
	switch ($args[$i]) {
		'-o' { $HAS_O = $true; $OutputDir = $args[$i+1] }
		'-f' { $HAS_F = $true; $Format = $args[$i+1] }
		'-q' { $HAS_Q = $true; $Quality = $args[$i+1] }
		'-h' { Show-Help; exit 0 }
	}
}

# ========== LOAD SAVED CONFIGURATION ==========
$ConfigPath = Join-Path $OutputDir $ConfigFile
if (Test-Path $ConfigPath) {
	try {
		$savedConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json
		Write-Blue "Loading saved configuration from: $ConfigPath"
		
		if (-not $HAS_O) { $OutputDir = $savedConfig.OutputDir }
		if (-not $HAS_F) { $Format = $savedConfig.Format }
		if (-not $HAS_Q) { $Quality = $savedConfig.Quality }
		
		Write-Green "[INFO] Using saved settings from: $ConfigPath"
		Write-Host "  Format: $Format"
		Write-Host "  Quality: $Quality"
		Write-Host ""
	} catch {
		Write-Yellow "Could not parse saved configuration, using defaults"
	}
}

# Validate quality
if ($Quality -notin @('low', 'mid', 'high')) {
	Write-Red "ERROR: Quality must be low, mid, or high"
	exit 1
}

# Validate format
$AudioFormats = 'mp3', 'm4a', 'aac', 'flac', 'wav', 'opus'
$VideoFormats = 'mp4', 'webm', 'mkv', 'avi', 'mov'
$FormatLower = $Format.ToLower()
if ($AudioFormats -contains $FormatLower) {
	$ConversionType = 'audio'
	Write-Blue "Target format: $FormatLower (audio)"
} elseif ($VideoFormats -contains $FormatLower) {
	$ConversionType = 'video'
	Write-Blue "Target format: $FormatLower (video)"
} else {
	Write-Red "ERROR: Unsupported format '$Format'"
	exit 1
}

# Set quality parameters for ffmpeg
switch ($Quality) {
	'low' {
		$AudioBitrate = "96k"
		$SampleRate = "22050"
		$VideoCRF = "28"
	}
	'mid' {
		$AudioBitrate = "192k"
		$SampleRate = "44100"
		$VideoCRF = "23"
	}
	'high' {
		$AudioBitrate = "320k"
		$SampleRate = "48000"
		$VideoCRF = "18"
	}
	default {
		$AudioBitrate = "192k"
		$SampleRate = "44100"
		$VideoCRF = "23"
	}
}
Write-Blue "Conversion quality: $Quality (audio: ${AudioBitrate}, ${SampleRate}Hz)"

# ========== SAVE CONFIGURATION IF CHANGED ==========
if ($HAS_F -or $HAS_Q) {
	# Load existing config to preserve other values
	$existingConfig = $null
	if (Test-Path $ConfigPath) {
		$existingConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json
	}
	
	$config = @{
		PlaylistUrl = if ($existingConfig) { $existingConfig.PlaylistUrl } else { "" }
		OutputDir = $OutputDir
		SleepInterval = if ($existingConfig) { $existingConfig.SleepInterval } else { 11 }
		Format = $Format
		Quality = $Quality
		EnableArchive = if ($existingConfig) { $existingConfig.EnableArchive } else { $false }
		LastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
	}
	
	$config | ConvertTo-Json | Set-Content $ConfigPath
	Write-Blue "Configuration updated in: $ConfigPath"
}

# ========== CHANGE TO OUTPUT DIRECTORY ==========
Push-Location $OutputDir -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) {
	Write-Red "ERROR: Cannot access directory: $OutputDir"
	exit 1
}

# ========== SET UP PATHS ==========
$ArchiveDir = ".archive_recovered"
$LogFile = ".recovered_moved.log"

# Initialize log file
if (-not (Test-Path $LogFile)) { New-Item $LogFile -ItemType File | Out-Null }

Write-Green "========================================="
Write-Green "Archive Recovery Processor"
Write-Green "========================================="
Write-Host "Source: $ArchiveDir"
Write-Host "Destination: $OutputDir"
Write-Host "Target format: $FormatLower"
Write-Host "Quality: $Quality"
Write-Host ""

# Check if archive directory exists
if (-not (Test-Path $ArchiveDir)) {
	Write-Yellow "Archive directory not found: $ArchiveDir"
	Pop-Location
	exit 0
}

# Count files
$TotalFiles = 0
$supportedExtensions = @('mp3', 'm4a', 'webm', 'opus', 'mp4', 'flac', 'wav', 'aac', 'mkv', 'avi', 'mov')
foreach ($file in Get-ChildItem -Path $ArchiveDir -File) {
	if ($file.Extension -and $supportedExtensions -contains $file.Extension.TrimStart('.').ToLower()) {
		$TotalFiles++
	}
}

if ($TotalFiles -eq 0) {
	Write-Yellow "No media files found in $ArchiveDir"
	Pop-Location
	exit 0
}

Write-Blue "Found $TotalFiles files to process"
Write-Host ""

$Processed = 0
$Converted = 0
$Failed = 0

# Process each file
foreach ($file in Get-ChildItem -Path $ArchiveDir -File) {
	$extension = $file.Extension.TrimStart('.').ToLower()
	if ($supportedExtensions -notcontains $extension) { continue }
	
	$Processed++
	$filename = $file.Name
	$nameWithoutExt = $file.BaseName
	
	Write-Cyan "[$Processed/$TotalFiles] Processing: $filename"
	
	# Always convert to target format (don't just move matching files)
	Write-Blue "  -> Converting $extension to $FormatLower..."
	
	$tempFile = Join-Path $OutputDir "$nameWithoutExt.$FormatLower"
	
	# Handle duplicates
	if (Test-Path $tempFile) {
		$base = $nameWithoutExt
		$counter = 1
		while (Test-Path (Join-Path $OutputDir "${base}_${counter}.$FormatLower")) {
			$counter++
		}
		$tempFile = Join-Path $OutputDir "${base}_${counter}.$FormatLower"
	}
	
	$conversionSuccess = $false
	
	if ($ConversionType -eq 'audio') {
		# Audio conversion with quality settings
		& $FfmpegExe -i $file.FullName -vn -ar $SampleRate -ac 2 -b:a $AudioBitrate $tempFile -y 2>$null
		if ($LASTEXITCODE -eq 0 -and (Test-Path $tempFile) -and (Get-Item $tempFile).Length -gt 0) {
			$conversionSuccess = $true
		}
	} else {
		# Video conversion with quality settings
		& $FfmpegExe -i $file.FullName -c:v libx264 -crf $VideoCRF -c:a aac -b:a $AudioBitrate $tempFile -y 2>$null
		if ($LASTEXITCODE -eq 0 -and (Test-Path $tempFile) -and (Get-Item $tempFile).Length -gt 0) {
			$conversionSuccess = $true
		}
	}
	
	if ($conversionSuccess) {
		Write-Green "  [OK] Converted to $FormatLower : $(Split-Path $tempFile -Leaf)"
		Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
		$Converted++
		Add-Content $LogFile "CONVERTED: $(Split-Path $tempFile -Leaf)"
	} else {
		Write-Red "  [FAILED] Conversion failed for: $filename"
		$Failed++
		Add-Content $LogFile "FAILED: $filename"
	}
}

# Clean up empty archive directory
if (Test-Path $ArchiveDir) {
	try {
		Remove-Item $ArchiveDir -Force -ErrorAction SilentlyContinue
		if (-not (Test-Path $ArchiveDir)) {
			Write-Blue "Removed empty archive_recovered directory"
		} else {
			$remaining = (Get-ChildItem $ArchiveDir -File).Count
			if ($remaining -gt 0) {
				Write-Yellow "Warning: $remaining files remain in $ArchiveDir"
			}
		}
	} catch { }
}

# ========== SUMMARY ==========
Write-Host ""
Write-Green "========================================="
Write-Green "PROCESSING COMPLETE"
Write-Green "========================================="
Write-Host "Total files processed: $Processed"
Write-Green "[OK] Converted to $FormatLower : $Converted"
Write-Red "[FAILED] Failed: $Failed"
Write-Host ""
Write-Host "Log saved to: $LogFile"

if ($Failed -gt 0) {
	Write-Host ""
	Write-Yellow "Failed files (check $LogFile for details):"
	Get-Content $LogFile | Select-String "FAILED:" | Select-Object -Last 5 | ForEach-Object { Write-Host "  $_" }
}

# ========== RESTORE ORIGINAL LOCATION ==========
Pop-Location