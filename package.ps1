<#
Builds the zip to upload to CurseForge and Wago: .release\AuctionCoach-<version>.zip

Only the AuctionCoach folder goes in. AuctionCoach_Data is left out on
purpose: the desktop app creates and updates it, and shipping the empty
placeholder would wipe every player's prices on each addon update.

Run from anywhere:
    powershell -ExecutionPolicy Bypass -File F:\AuctionCoach\auction-coach-addon\package.ps1
#>

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Root = $PSScriptRoot
$Addon = Join-Path $Root "AuctionCoach"
$Toc = Join-Path $Addon "AuctionCoach.toc"

$match = Select-String -Path $Toc -Pattern '^## Version:\s*(\S+)' | Select-Object -First 1
if (-not $match) { Write-Host "No ## Version line in $Toc" -ForegroundColor Red; exit 1 }
$Version = $match.Matches[0].Groups[1].Value

# Every file the .toc loads must exist, or players get a load error.
$missing = Get-Content $Toc | Where-Object { $_ -match '^[^#\s].*\.(lua|xml)\s*$' } |
    Where-Object { -not (Test-Path (Join-Path $Addon $_.Trim())) }
if ($missing) { Write-Host "Listed in the .toc but missing: $($missing -join ', ')" -ForegroundColor Red; exit 1 }

$OutDir = Join-Path $Root ".release"
New-Item -ItemType Directory -Force $OutDir | Out-Null
$Zip = Join-Path $OutDir "AuctionCoach-$Version.zip"
if (Test-Path $Zip) { Remove-Item $Zip }

# Built entry by entry so paths use "/" (Compress-Archive in Windows
# PowerShell 5.1 writes "\", which some unzip tools mishandle).
$archive = [System.IO.Compression.ZipFile]::Open($Zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $count = 0
    Get-ChildItem $Addon -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($Root.Length + 1).Replace("\", "/")
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $_.FullName, $relative, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        $count++
    }
} finally {
    $archive.Dispose()
}

$size = [math]::Round((Get-Item $Zip).Length / 1KB)
Write-Host "Built $Zip ($count files, $size KB)" -ForegroundColor Green
