# ========== ARGUMENT PARSING (MUST BE FIRST) ==========
param(
	[string]$p,
	[string]$o,
	[int]$t,
	[string]$f,
	[string]$q,
	[string]$b,
	[switch]$a,
	[switch]$h
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Browser = "firefox"  # Default

# ========== CHECK AND INSTALL WINGET (Windows 10/11) ==========
function Install-Winget {
    Write-Host "[!] Checking if winget is available..." -ForegroundColor Yellow
    
    # Check if winget is already available
    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetPath) {
        Write-Host "[OK] winget found" -ForegroundColor Green
        return $true
    }
    
    # winget is part of App Installer on Windows 10/11
    Write-Host "[!] winget not found. Attempting to install App Installer..." -ForegroundColor Yellow
    
    # Check Windows version
    $osInfo = Get-ComputerInfo -ErrorAction SilentlyContinue
    $buildNumber = [Environment]::OSVersion.Version.Build
    
    if ($buildNumber -ge 18362) {
        Write-Host "[!] Windows 10/11 detected. Installing App Installer from Microsoft Store..." -ForegroundColor Yellow
        
        # Try to install App Installer via Microsoft Store link
        $wingetUrl = "https://aka.ms/getwinget"
        try {
            Start-Process $wingetUrl -Wait -NoNewWindow
            Write-Host "[OK] Please follow the Microsoft Store prompt to install App Installer" -ForegroundColor Green
            Write-Host "[!] After installation, please run this script again" -ForegroundColor Yellow
            pause
            exit 0
        } catch {
            Write-Host "[WARN] Could not automatically install winget" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "[WARN] winget requires Windows 10 1809 (build 18362) or later" -ForegroundColor Red
        return $false
    }
    return $false
}

# ========== YT-DLP INSTALLATION WITH WINGET ==========
if (-not (Test-Path (Join-Path $ScriptDir 'yt-dlp.exe'))) {
    Write-Host "[!] yt-dlp.exe not found. Attempting to install with winget..." -ForegroundColor Yellow
    
    # Ensure winget is available
    if (Install-Winget) {
        Write-Host "[!] Installing yt-dlp via winget..." -ForegroundColor Yellow
        
        # Try to install yt-dlp using winget
        $installResult = & winget install yt-dlp.yt-dlp --silent --accept-package-agreements --accept-source-agreements 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] yt-dlp installed successfully via winget" -ForegroundColor Green
            
            # Find where winget installed yt-dlp
            $wingetPath = & winget list yt-dlp.yt-dlp --source winget | Select-String "yt-dlp"
            $ytDlpPath = & where.exe yt-dlp 2>$null | Select-Object -First 1
            
            if ($ytDlpPath) {
                Copy-Item $ytDlpPath -Destination (Join-Path $ScriptDir 'yt-dlp.exe') -Force
                Write-Host "[OK] yt-dlp.exe copied to script directory" -ForegroundColor Green
            }
        } else {
            Write-Host "[WARN] winget installation failed. Falling back to direct download..." -ForegroundColor Yellow
        }
    }
    
    # Fallback: Direct download if winget failed
    if (-not (Test-Path (Join-Path $ScriptDir 'yt-dlp.exe'))) {
        Write-Host "[!] Downloading standalone yt-dlp.exe (with built-in JS runtime)..." -ForegroundColor Yellow
        $ytDlpUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
        try {
            Invoke-WebRequest -Uri $ytDlpUrl -OutFile (Join-Path $ScriptDir 'yt-dlp.exe') -UseBasicParsing
            Write-Host "[OK] yt-dlp.exe downloaded successfully (standalone version with JS runtime)" -ForegroundColor Green
        } catch {
            Write-Host "ERROR: Failed to download yt-dlp.exe" -ForegroundColor Red
            exit 1
        }
    }
}
$YtDlpExe = Join-Path $ScriptDir 'yt-dlp.exe'

# ========== FFMPEG INSTALLATION WITH WINGET ==========
$FfmpegExe = Join-Path $ScriptDir 'ffmpeg.exe'
if (-not (Test-Path $FfmpegExe)) {
    Write-Host "[!] ffmpeg.exe not found. Attempting to install with winget..." -ForegroundColor Yellow
    
    if (Install-Winget) {
        Write-Host "[!] Installing ffmpeg via winget..." -ForegroundColor Yellow
        
        $installResult = & winget install ffmpeg --silent --accept-package-agreements --accept-source-agreements 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] ffmpeg installed successfully via winget" -ForegroundColor Green
            
            # Find where winget installed ffmpeg
            $ffmpegPath = & where.exe ffmpeg 2>$null | Select-Object -First 1
            if ($ffmpegPath) {
                Copy-Item $ffmpegPath -Destination $FfmpegExe -Force
                Write-Host "[OK] ffmpeg.exe copied to script directory" -ForegroundColor Green
            }
        } else {
            Write-Host "[WARN] winget installation failed. Falling back to manual download..." -ForegroundColor Yellow
        }
    }
    
    # Fallback: Direct download if winget failed
    if (-not (Test-Path $FfmpegExe)) {
        Write-Host "[!] ffmpeg.exe not found. Downloading latest static Windows build..." -ForegroundColor Yellow
        $ffmpegZipUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
        $ffmpegZip = Join-Path $ScriptDir 'ffmpeg-release-essentials.zip'
        try {
            Invoke-WebRequest -Uri $ffmpegZipUrl -OutFile $ffmpegZip -UseBasicParsing
            Write-Host "[OK] ffmpeg zip downloaded. Extracting..." -ForegroundColor Green
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ffmpegZip, $ScriptDir)
            $ffmpegFound = Get-ChildItem -Path $ScriptDir -Recurse -Filter ffmpeg.exe | Select-Object -First 1
            if ($ffmpegFound) {
                Move-Item -Force $ffmpegFound.FullName $FfmpegExe
                Write-Host "[OK] ffmpeg.exe extracted and moved." -ForegroundColor Green
            } else {
                Write-Host "ERROR: ffmpeg.exe not found after extraction." -ForegroundColor Red
                exit 1
            }
            Remove-Item $ffmpegZip -Force
            Get-ChildItem -Path $ScriptDir -Directory | Where-Object { $_.Name -like 'ffmpeg-*' } | Remove-Item -Recurse -Force
        } catch {
            Write-Host "ERROR: Failed to download or extract ffmpeg." -ForegroundColor Red
            exit 1
        }
    }
}
if (-not (Test-Path $FfmpegExe)) {
    Write-Host "ERROR: ffmpeg.exe is required but could not be installed. Exiting." -ForegroundColor Red
    exit 1
}

# ========== DENO INSTALLATION (Fallback - direct download) ==========
function Install-Deno {
    Write-Host "[!] Deno not found. Installing Deno (JavaScript runtime for yt-dlp)..." -ForegroundColor Yellow
    
    $denoUrl = 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip'
    $denoZip = Join-Path $ScriptDir 'deno.zip'
    $denoExe = Join-Path $ScriptDir 'deno.exe'
    
    try {
        Invoke-WebRequest -Uri $denoUrl -OutFile $denoZip -UseBasicParsing
        Write-Host "[OK] Deno zip downloaded. Extracting..." -ForegroundColor Green
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($denoZip, $ScriptDir)
        Remove-Item $denoZip -Force
        Write-Host "[OK] Deno installed to: $denoExe" -ForegroundColor Green
        
        # Add deno to PATH for this session
        $env:Path = "$ScriptDir;$env:Path"
        
        # Verify installation
        & $denoExe --version
        Write-Host "[OK] Deno is ready" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Deno installation failed. yt-dlp may still work but archive recovery might have issues." -ForegroundColor Yellow
    }
}

# Check if Deno is available (for archive recovery)
$denoExe = Join-Path $ScriptDir 'deno.exe'
if (-not (Test-Path $denoExe)) {
    $systemDeno = Get-Command deno -ErrorAction SilentlyContinue
    if (-not $systemDeno) {
        Install-Deno
    } else {
        Write-Host "[OK] Deno found in system PATH" -ForegroundColor Green
    }
}

# ========== DEFAULT CONFIGURATION ==========
$OutputDir = Get-Location
$SleepInterval = 11
$Format = 'mp3'
$Quality = 'mid'
$PlaylistUrl = $null
$EnableArchive = $false
$TakDataDir = ".TakData"

# ========== COLOR FUNCTIONS ========== 
function Write-Red { Write-Host $args -ForegroundColor Red }
function Write-Green { Write-Host $args -ForegroundColor Green }
function Write-Yellow { Write-Host $args -ForegroundColor Yellow }
function Write-Blue { Write-Host $args -ForegroundColor Blue }
function Write-Cyan { Write-Host $args -ForegroundColor Cyan }
function Write-Magenta { Write-Host $args -ForegroundColor Magenta }

function Show-Help {
	Write-Host "Usage: .\Download-Playlist.ps1 -p <PLAYLIST_URL> [-o <OUTPUT_DIR>] [-t <SECONDS>] [-f <FORMAT>] [-q <QUALITY>] [-b <BROWSER>] [-a] [-h]" -ForegroundColor Cyan
	Write-Host ""
	Write-Host "Required:"
	Write-Host "  -p <URL>        YouTube playlist URL"
	Write-Host ""
	Write-Host "Options:"
	Write-Host "  -o <DIR>        Output directory (default: current directory)"
	Write-Host "  -t <SECONDS>    Sleep between downloads (default: 11, 0 = no delay)"
	Write-Host "  -f <FORMAT>     Output format: mp3, m4a, opus, flac, mp4, webm, etc. (default: mp3)"
	Write-Host "  -q <QUALITY>    Quality: low, mid, high (default: mid)"
	Write-Host "  -b <BROWSER>    Browser for cookies: firefox, chrome, chromium, brave, edge, opera, vivaldi, safari, none (default: firefox)"
	Write-Host "  -a              Enable archive recovery for deleted videos"
	Write-Host "  -h             Show this help"
	Write-Host ""
	Write-Host "Note: Settings and logs are stored in '${TakDataDir}' subfolder"
	Write-Host "Note: yt-dlp and ffmpeg are installed automatically via winget if available"
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

# ========== PARSE COMMAND LINE ARGUMENTS ==========
$HAS_P = $PSBoundParameters.ContainsKey('p')
$HAS_O = $PSBoundParameters.ContainsKey('o')
$HAS_T = $PSBoundParameters.ContainsKey('t')
$HAS_F = $PSBoundParameters.ContainsKey('f')
$HAS_Q = $PSBoundParameters.ContainsKey('q')
$HAS_B = $PSBoundParameters.ContainsKey('b')
$HAS_A = $PSBoundParameters.ContainsKey('a')
$HAS_H = $PSBoundParameters.ContainsKey('h')

if ($HAS_H) { Show-Help; exit 0 }

if ($HAS_P) { $PlaylistUrl = $p }
if ($HAS_O) { $OutputDir = $o }
if ($HAS_T) { $SleepInterval = $t }
if ($HAS_F) { $Format = $f }
if ($HAS_Q) { $Quality = $q }
if ($HAS_B) { $Browser = $b }
if ($HAS_A) { $EnableArchive = $a }

# Normalize path
$OutputDir = $OutputDir -replace '/', '\'

# ========== IF -p WAS PROVIDED, USE IT AND SAVE CONFIG ==========
if ($HAS_P) {
	Write-Green "[INFO] Using provided playlist URL"
	
	# Create output directory if needed
	if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
	
	# Get TakData directory path
	$TakDataPath = Get-TakDataPath -outputDir $OutputDir
	$ConfigFile = Join-Path $TakDataPath "download_config.json"
	
	# Save configuration
	$config = @{
		PlaylistUrl = $PlaylistUrl
		OutputDir = $OutputDir
		SleepInterval = $SleepInterval
		Format = $Format
		Quality = $Quality
		Browser = $Browser
		EnableArchive = $EnableArchive
		LastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
	}
	$config | ConvertTo-Json | Set-Content $ConfigFile
	Write-Blue "Configuration saved to: $ConfigFile"
}
else {
	# Try to load saved configuration
	$TakDataPath = Get-TakDataPath -outputDir $OutputDir
	$ConfigFile = Join-Path $TakDataPath "download_config.json"
	
	if (Test-Path $ConfigFile) {
		$savedConfig = Get-Content $ConfigFile -Raw | ConvertFrom-Json
		Write-Green "[INFO] Found saved configuration from: $($savedConfig.LastUpdated)"
		
		$PlaylistUrl = $savedConfig.PlaylistUrl
		if (-not $HAS_O) { $OutputDir = $savedConfig.OutputDir }
		if (-not $HAS_T) { $SleepInterval = $savedConfig.SleepInterval }
		if (-not $HAS_F) { $Format = $savedConfig.Format }
		if (-not $HAS_Q) { $Quality = $savedConfig.Quality }
		if (-not $HAS_B) { 
			if ($savedConfig.PSObject.Properties.Name -contains 'Browser') {
				$Browser = $savedConfig.Browser 
			}
		}
		if (-not $HAS_A) { $EnableArchive = $savedConfig.EnableArchive }
		
		Write-Green "[INFO] Using saved settings:"
		Write-Host "  Playlist URL: $PlaylistUrl"
		Write-Host "  Format: $Format"
		Write-Host "  Quality: $Quality"
		Write-Host "  Browser: $Browser"
		Write-Host "  Delay: ${SleepInterval}s"
		Write-Host "  Archive recovery: $(if ($EnableArchive) { 'ON' } else { 'OFF' })"
		Write-Host ""
	} else {
		Write-Red "ERROR: Playlist URL is required on first run"
		Show-Help
		exit 1
	}
}

# Validate required values
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

# Clean URL (remove tracking parameters)
$PlaylistUrl = $PlaylistUrl -replace '&si=[^&]*', '' -replace '\?si=[^&]*', ''

# ========== CREATE OUTPUT DIRECTORY ==========
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# ========== CHANGE TO OUTPUT DIRECTORY ==========
Push-Location $OutputDir

# ========== CREATE TAKDATA DIRECTORY AND SET LOG FILES ==========
$TakDataPath = Get-TakDataPath -outputDir $OutputDir
$DownloadedLog = Join-Path $TakDataPath "downloaded_ids.txt"
$FailedLog = Join-Path $TakDataPath "failed_ids.txt"
$PermanentlyFailedLog = Join-Path $TakDataPath "permanently_failed_ids.txt"
$RecoveredLog = Join-Path $TakDataPath "recovered_ids.txt"
$VideoIdsFile = Join-Path $TakDataPath "playlist_videos.txt"
$ArchiveDir = Join-Path $TakDataPath "archive_recovered"

foreach ($file in @($DownloadedLog, $FailedLog, $PermanentlyFailedLog, $RecoveredLog)) { 
	if (-not (Test-Path $file)) { New-Item $file -ItemType File | Out-Null } 
}
if (-not (Test-Path $ArchiveDir)) { New-Item -ItemType Directory -Path $ArchiveDir | Out-Null }

Write-Blue "TakData directory: $TakDataPath"
Write-Blue "Log files stored in TakData subfolder"

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

# ========== HELPER FUNCTIONS ==========
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

# ============================================================================
# ========== ARCHIVE SEARCH FUNCTIONS (FIXED) ================================
# ============================================================================
# These functions now try multiple URL variants and use the correct APIs:
#   - Wayback: CDX API with matchType=prefix across all YouTube URL forms
#   - Archive.org: Advanced Search API to find items by video ID
#   - GhostArchive: Direct download attempt (no pre-check that can fail on Cloudflare)
# ============================================================================

function Search-Wayback {
	param(
		[string]$video_id,
		[string]$outputFile
	)
	
	Write-Blue "     -> Checking Wayback Machine..."
	
	# Try multiple URL variants since Wayback captures videos under many formats
	$urlVariants = @(
		"youtube.com/watch?v=$video_id",
		"www.youtube.com/watch?v=$video_id",
		"youtu.be/$video_id",
		"m.youtube.com/watch?v=$video_id",
		"youtube.com/embed/$video_id",
		"www.youtube.com/embed/$video_id"
	)
	
	$foundTimestamp = $null
	$foundOriginal = $null
	$matchedVariant = $null
	
	foreach ($variant in $urlVariants) {
		try {
			# Use matchType=prefix to catch extra query params
			$cdxUrl = "https://web.archive.org/cdx/search/cdx?url=$variant&matchType=prefix&output=json&limit=5&fl=timestamp,original,statuscode&filter=statuscode:200"
			
			$response = Invoke-WebRequest -Uri $cdxUrl -UseBasicParsing -TimeoutSec 20 -ErrorAction SilentlyContinue
			if (-not $response -or -not $response.Content) { continue }
			
			$content = $response.Content.Trim()
			if ($content -eq '[]' -or $content -eq '' -or $content -eq 'null') { continue }
			
			$data = $content | ConvertFrom-Json
			if ($data.Count -gt 1) {
				# First row is headers, second row is first snapshot
				# Format: [["timestamp","original","statuscode"],["20230101...","http://...","200"],...]
				$firstSnap = $data[1]
				$foundTimestamp = $firstSnap[0]
				$foundOriginal = $firstSnap[1]
				$matchedVariant = $variant
				break
			}
		} catch {
			continue
		}
	}
	
	if (-not $foundTimestamp -or -not $foundOriginal) {
		Write-Red "     [X] Not found on Wayback Machine"
		return $false
	}
	
	# Build the Wayback URL using the ACTUAL archived original URL
	$waybackUrl = "https://web.archive.org/web/${foundTimestamp}if_/$foundOriginal"
	
	Write-Green "     [OK] Found on Wayback (capture $foundTimestamp)"
	Write-Blue "       Matched variant: $matchedVariant"
	Write-Blue "       URL: $waybackUrl"
	
	# Try to download
	& $YtDlpExe --no-warnings --no-playlist --no-check-certificate --output $outputFile $waybackUrl 2>$null
	if ($LASTEXITCODE -eq 0) {
		Write-Green "     Download successful from Wayback Machine"
		return $true
	}
	
	return $false
}

function Search-GhostArchive {
	param(
		[string]$video_id,
		[string]$outputFile
	)
	
	Write-Blue "     -> Checking GhostArchive..."
	
	$ghostUrl = "https://ghostarchive.org/varchive/youtube/$video_id"
	
	# Skip the pre-check and just try the download.
	# GhostArchive returns 200 for real videos and 404/redirect for missing ones.
	# The old HEAD check returned 403 from Cloudflare even when the video was downloadable.
	& $YtDlpExe --no-warnings --no-playlist --no-check-certificate --socket-timeout 20 --output $outputFile $ghostUrl 2>$null
	
	if ($LASTEXITCODE -eq 0) {
		Write-Green "     [OK] Downloaded from GhostArchive"
		return $true
	}
	
	Write-Red "     [X] Not found on GhostArchive"
	return $false
}

function Search-ArchiveOrg {
	param(
		[string]$video_id,
		[string]$outputFile
	)
	
	Write-Blue "     -> Checking Archive.org..."
	
	# First try the common identifier format (fast path)
	$directUrl = "https://archive.org/details/youtube-$video_id"
	& $YtDlpExe --no-warnings --no-playlist --no-check-certificate --socket-timeout 20 -f "bestvideo+bestaudio/best" --output $outputFile $directUrl 2>$null
	
	if ($LASTEXITCODE -eq 0) {
		Write-Green "     [OK] Downloaded from Archive.org (direct)"
		return $true
	}
	
	# Fallback: search Archive.org for items mentioning the video ID
	try {
		$searchUrl = "https://archive.org/advancedsearch.php?q=youtube+${video_id}&fl[]=identifier&rows=5&output=json"
		$searchResponse = Invoke-WebRequest -Uri $searchUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction SilentlyContinue
		
		if ($searchResponse -and $searchResponse.Content) {
			$searchData = $searchResponse.Content | ConvertFrom-Json
			$docs = $searchData.response.docs
			
			if ($docs -and $docs.Count -gt 0) {
				$identifier = $docs[0].identifier
				
				if ($identifier) {
					$itemUrl = "https://archive.org/details/$identifier"
					Write-Blue "       Found Archive.org item: $identifier"
					
					& $YtDlpExe --no-warnings --no-playlist --no-check-certificate --socket-timeout 20 -f "bestvideo+bestaudio/best" --output $outputFile $itemUrl 2>$null
					
					if ($LASTEXITCODE -eq 0) {
						Write-Green "     [OK] Downloaded from Archive.org (search)"
						return $true
					}
				}
			}
		}
	} catch {
		# Ignore search errors and fall through
	}
	
	Write-Red "     [X] Not found on Archive.org"
	return $false
}

function Search-Hobune {
	param(
		[string]$video_id,
		[string]$outputFile
	)
	
	Write-Blue "     -> Checking Hobune.stream..."
	
	$hobuneUrl = "https://hobune.stream/yt/${video_id}.mp4"
	
	# Try direct download
	& $YtDlpExe --no-warnings --no-playlist --no-check-certificate --socket-timeout 15 --output $outputFile $hobuneUrl 2>$null
	
	if ($LASTEXITCODE -eq 0) {
		Write-Green "     [OK] Downloaded from Hobune.stream"
		return $true
	}
	
	Write-Red "     [X] Not found on Hobune.stream"
	return $false
}

# Master archive search function - tries all sources in order
function Search-Archive {
	param([string]$video_id)
	
	Write-Blue "  -> Searching archives for $video_id..."
	
	if (-not (Test-Path $ArchiveDir)) { New-Item -ItemType Directory -Path $ArchiveDir | Out-Null }
	
	$outputFile = Join-Path $ArchiveDir "%(uploader)s - %(title)s.%(ext)s"
	
	# Try 1: GhostArchive
	if (Search-GhostArchive -video_id $video_id -outputFile $outputFile) {
		return $true
	}
	
	# Try 2: Archive.org
	if (Search-ArchiveOrg -video_id $video_id -outputFile $outputFile) {
		return $true
	}
	
	# Try 3: Wayback Machine (FIXED - multi-variant CDX query)
	if (Search-Wayback -video_id $video_id -outputFile $outputFile) {
		return $true
	}
	
	# Try 4: Hobune.stream
	if (Search-Hobune -video_id $video_id -outputFile $outputFile) {
		return $true
	}
	
	Write-Red "     Not found in any archive"
	return $false
}

# ============================================================================
# ========== EXTRACT VIDEO IDS ================================================
# ============================================================================

Write-Green "========================================="
Write-Green "Tak Playlist Downloader"
Write-Green "========================================="
Write-Host "Output directory: $OutputDir"
Write-Host "TakData directory: $TakDataPath"
Write-Host "Format: $FormatLower ($DownloadType)"
Write-Host "Quality: $Quality"
Write-Host "Browser: $Browser"
Write-Host "Delay: ${SleepInterval}s"
Write-Host "Archive recovery: $(if ($EnableArchive) { 'ON' } else { 'OFF' })"
Write-Host ""

if (-not (Test-Internet)) { Wait-ForInternet }

Write-Blue "Fetching playlist..."
Remove-Item $VideoIdsFile -ErrorAction SilentlyContinue

if ($Browser -ne "none") {
	& $YtDlpExe --cookies-from-browser $Browser --flat-playlist --print "%(id)s" $PlaylistUrl | Set-Content $VideoIdsFile
	if (-not (Get-Content $VideoIdsFile | Where-Object { $_.Trim() })) {
		& $YtDlpExe --cookies-from-browser $Browser --extractor-args youtubetab:skip=authcheck --flat-playlist --print "%(id)s" $PlaylistUrl | Set-Content $VideoIdsFile
	}
} else {
	& $YtDlpExe --flat-playlist --print "%(id)s" $PlaylistUrl | Set-Content $VideoIdsFile
	if (-not (Get-Content $VideoIdsFile | Where-Object { $_.Trim() })) {
		& $YtDlpExe --extractor-args youtubetab:skip=authcheck --flat-playlist --print "%(id)s" $PlaylistUrl | Set-Content $VideoIdsFile
	}
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
	
	# ---- Robust download with multiple fallback methods ----
	$downloadSuccess = $false
	
	# Method 1: Standard with cookies (if browser specified)
	if ($Browser -ne "none") {
		$args = @()
		$args += '--cookies-from-browser'; $args += $Browser
		$args += '--extractor-args'; $args += 'youtubetab:skip=authcheck'
		foreach ($part in $YtdlpArgs -split ' ') { if ($part) { $args += $part } }
		$args += '--embed-thumbnail'
		$args += '--add-metadata'
		$args += '--output'; $args += $OutputTemplate
		$args += '--no-overwrites'
		$args += '--continue'
		$args += '--no-check-certificate'
		$args += "https://youtube.com/watch?v=$video_id"
		
		try {
			& $YtDlpExe @args 2>&1 | Out-Null
			if ($LASTEXITCODE -eq 0) { $downloadSuccess = $true }
		} catch { }
	}
	
	# Method 2: Without cookies but with user agent
	if (-not $downloadSuccess) {
		$args = @()
		$args += '--user-agent'; $args += 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
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
			if ($LASTEXITCODE -eq 0) { $downloadSuccess = $true }
		} catch { }
	}
	
	# Method 3: Geo-bypass
	if (-not $downloadSuccess) {
		$args = @()
		$args += '--geo-bypass'
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
			if ($LASTEXITCODE -eq 0) { $downloadSuccess = $true }
		} catch { }
	}
	
	# Method 4: Android client (bypasses some restrictions)
	if (-not $downloadSuccess) {
		$args = @()
		$args += '--extractor-args'; $args += 'youtube:player_client=android'
		foreach ($part in $YtdlpArgs -split ' ') { if ($part) { $args += $part } }
		$args += '--embed-thumbnail'
		$args += '--add-metadata'
		$args += '--output'; $args += $OutputTemplate
		$args += '--no-overwrites'
		$args += '--continue'
		$args += "https://youtube.com/watch?v=$video_id"
		
		try {
			& $YtDlpExe @args 2>&1 | Out-Null
			if ($LASTEXITCODE -eq 0) { $downloadSuccess = $true }
		} catch { }
	}
	
	if ($downloadSuccess) {
		Write-Green "  [OK] Success - added to log"
		Add-Content $DownloadedLog $video_id
		Remove-FromFailedLog -video_id $video_id
		$YoutubeSuccess++
	} else {
		Write-Red "  [X] YouTube failed after all attempts"
		
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
Write-Host "Settings and logs saved to: $TakDataPath"
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