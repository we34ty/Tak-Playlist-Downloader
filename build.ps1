# build.ps1
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tak Playlist Downloader - Build Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check Python
try {
    $pythonVersion = & python --version 2>&1
    Write-Host "Python found: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Python not found!" -ForegroundColor Red
    Write-Host "Please install Python from https://python.org" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Install/upgrade required packages
Write-Host "`nInstalling/upgrading required packages..." -ForegroundColor Yellow

$packages = @("schedule", "pystray", "pillow", "pyinstaller", "ttkthemes")
$failed = $false

foreach ($pkg in $packages) {
    Write-Host "  Installing $pkg..." -ForegroundColor Gray
    $result = & pip install --upgrade $pkg 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to install $pkg!" -ForegroundColor Red
        $failed = $true
    }
}

if ($failed) {
    Write-Host "`nFailed to install some packages!" -ForegroundColor Red
    Write-Host "Try running: pip install schedule pystray pillow pyinstaller ttkthemes" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "`nAll packages installed successfully!" -ForegroundColor Green

# Clean previous build
Write-Host "`nCleaning previous build..." -ForegroundColor Yellow
if (Test-Path "build") { Remove-Item -Recurse -Force "build" }
if (Test-Path "dist") { Remove-Item -Recurse -Force "dist" }
if (Test-Path "*.spec") { Remove-Item -Force *.spec }

# Build executable
Write-Host "`nBuilding executable (this may take a few minutes)..." -ForegroundColor Yellow

& pyinstaller --onefile --windowed `
    --name "Tak-Playlist-Downloader" `
    --hidden-import=schedule `
    --hidden-import=pystray `
    --hidden-import=PIL `
    --hidden-import=PIL.Image `
    --hidden-import=PIL.ImageDraw `
    --hidden-import=tkinter `
    --hidden-import=threading `
    --hidden-import=subprocess `
    --hidden-import=json `
    --hidden-import=datetime `
    --hidden-import=pathlib `
    --hidden-import=uuid `
    --hidden-import=queue `
    --hidden-import=atexit `
    --hidden-import=getpass `
    --collect-all schedule `
    --collect-all pystray `
    "Tak-Playlist-Downloader.py"

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "BUILD FAILED!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "BUILD SUCCESSFUL!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Get file size
$exePath = "dist\Tak-Playlist-Downloader.exe"
if (Test-Path $exePath) {
    $size = [math]::Round((Get-Item $exePath).Length / 1MB, 2)
    Write-Host "Executable: $exePath" -ForegroundColor White
    Write-Host "Size: ${size} MB" -ForegroundColor White
    Write-Host ""
}

# Copy required scripts
Write-Host "Copying required PowerShell scripts..." -ForegroundColor Yellow

$scripts = @("Download-Playlist.ps1", "Retry-Failed.ps1", "Move-Recovered.ps1")
foreach ($script in $scripts) {
    if (Test-Path $script) {
        Copy-Item $script "dist\" -Force
        Write-Host "  [OK] $script" -ForegroundColor Green
    } else {
        Write-Host "  $script not found!" -ForegroundColor Red
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "BUILD COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "The executable is in the 'dist' folder" -ForegroundColor White
Write-Host ""
Read-Host "Press Enter to exit"