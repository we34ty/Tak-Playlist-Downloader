# Tak Move Recovered Files (PowerShell)

param(
    [string]$OutputDir = (Get-Location).Path,
    [string]$Format = "mp3"
)

function Show-Help {
    Write-Host "Usage: .\Move-Recovered.ps1 [-OutputDir <DIR>] [-Format <mp3|mp4|flac|etc>]"
    Write-Host "\nOptions:"
    Write-Host "  -OutputDir     Output directory (default: current directory)"
    Write-Host "  -Format        Target format for conversion (default: mp3)"
}

$ArchiveDir = Join-Path $OutputDir 'archive_recovered'
if (!(Test-Path $ArchiveDir)) {
    Write-Host "Archive directory not found: $ArchiveDir"
    exit 1
}

$Files = Get-ChildItem -Path $ArchiveDir -File
if ($Files.Count -eq 0) {
    Write-Host "No media files found in $ArchiveDir"
    exit 0
}

$Processed = 0
foreach ($file in $Files) {
    $Processed++
    $ext = $file.Extension.TrimStart('.')
    $base = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $destFile = Join-Path $OutputDir "$base.$Format"
    if ($ext -ieq $Format) {
        # Move if already in target format
        $finalDest = $destFile
        $counter = 1
        while (Test-Path $finalDest) {
            $finalDest = Join-Path $OutputDir ("{0}_{1}.{2}" -f $base, $counter, $Format)
            $counter++
        }
        Move-Item $file.FullName $finalDest
        Write-Host "[$Processed] Moved: $($file.Name) -> $([System.IO.Path]::GetFileName($finalDest))"
    } else {
        # Convert using ffmpeg
        $tempFile = $destFile
        $counter = 1
        while (Test-Path $tempFile) {
            $tempFile = Join-Path $OutputDir ("{0}_{1}.{2}" -f $base, $counter, $Format)
            $counter++
        }
        $ffmpegCmd = "ffmpeg -i `"$($file.FullName)`" -vn -ar 44100 -ac 2 -b:a 192k `"$tempFile`" -y"
        if (Invoke-Expression $ffmpegCmd) {
            Remove-Item $file.FullName
            Write-Host "[$Processed] Converted: $($file.Name) -> $([System.IO.Path]::GetFileName($tempFile))"
        } else {
            Write-Host "[$Processed] Conversion failed: $($file.Name)"
        }
    }
}
Write-Host "\nPROCESSING COMPLETE! Files saved to: $OutputDir"
