# Build.ps1 - Build all PhotoDewey projects
#
# Builds the main application and all extensions in Release configuration.
# Any project that fails to build is reported in the summary; others continue.
#
# Usage:
#   .\Build.ps1
#   .\Build.ps1 -Configuration Debug

param(
    [string]$Configuration = "Release"
)

if (-not $PSBoundParameters.ContainsKey('Configuration')) {
    Write-Host "No parameters specified. Building with defaults."
    Write-Host "  -Configuration  Build configuration (default: Release | options: Debug, Release)"
    Write-Host ""
}

$script:results = [System.Collections.Generic.List[PSCustomObject]]::new()

function Build-Project {
    param([string]$Label, [string]$Path)

    Write-Host ""
    Write-Host "Building $Label..."

    dotnet build $Path -c $Configuration --nologo -v quiet
    if ($LASTEXITCODE -eq 0) {
        $script:results.Add([PSCustomObject]@{ Project = $Label; Result = "OK" })
    } else {
        $script:results.Add([PSCustomObject]@{ Project = $Label; Result = "FAILED" })
    }
}

Write-Host ""
Write-Host "Building application..."
Build-Project "Application (Windows)"        "Application\Windows UI\PhotoDewey.sln"
Build-Project "Application (Cross-platform)" "Application\PhotoDewey Cross-platform.sln"

Write-Host ""
Write-Host "Building extensions..."
Build-Project "AutoOptimize"    "Extensions\AutoOptimize\Source\AutoOptimize.slnx"
Build-Project "Filters"         "Extensions\Filters\Source\Filters.csproj"
Build-Project "ToneAdjustments" "Extensions\ToneAdjustments\Source\ToneAdjustments.csproj"

Write-Host ""
Write-Host "=== Summary ==="
$script:results | Format-Table -Property Project, Result -AutoSize

$failed = $script:results | Where-Object { $_.Result -ne "OK" }
if ($failed) {
    Write-Host "$($failed.Count) project(s) failed to build." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All projects built successfully." -ForegroundColor Green
}
