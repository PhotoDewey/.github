# Build.ps1 - Build all PhotoDewey projects
#
# Builds the main application and all extensions in Release configuration.
# Any project that fails to build is reported in the summary; others continue.
#
# Usage:
#   .\Build.ps1
#   .\Build.ps1 -Target Windows
#   .\Build.ps1 -Target All -Configuration Debug

param(
    [string]$Configuration = "Release",
    [string]$Target        = "All"
)

# ── Target definitions ────────────────────────────────────────────────────────
# Each entry: Label, Path, Group (used to select by group name)
$allTargets = @(
    [PSCustomObject]@{ Label = "Application"; Path = "Application\Application.sln";                                Group = "Application" }
    [PSCustomObject]@{ Label = "AutoOptimize";  Path = "Extensions\AutoOptimize\Source\AutoOptimize.slnx";         Group = "Extensions"  }
    [PSCustomObject]@{ Label = "Filters";       Path = "Extensions\Filters\Source\Filters.csproj";                 Group = "Extensions"  }
    [PSCustomObject]@{ Label = "ToneAdjustments"; Path = "Extensions\ToneAdjustments\Source\ToneAdjustments.csproj"; Group = "Extensions" }
)

$validTargets = @("All", "Application", "Extensions", "AutoOptimize", "Filters", "ToneAdjustments")

# ── Show options whenever no parameters are passed ────────────────────────────
if ($PSBoundParameters.Count -eq 0) {
    Write-Host "No parameters specified. Building with defaults."
    Write-Host ""
    Write-Host "  -Target         Which projects to build (default: All)"
    Write-Host "                    All             - Everything"
    Write-Host "                    Application     - Application only"
    Write-Host "                    Extensions      - All extensions"
    Write-Host "                    AutoOptimize    - AutoOptimize extension only"
    Write-Host "                    Filters         - Filters extension only"
    Write-Host "                    ToneAdjustments - ToneAdjustments extension only"
    Write-Host ""
    Write-Host "  -Configuration  Build configuration (default: Release | options: Debug, Release)"
    Write-Host ""
}

# ── Validate target ───────────────────────────────────────────────────────────
if ($Target -notin $validTargets) {
    Write-Host "Unknown target '$Target'. Valid targets: $($validTargets -join ', ')" -ForegroundColor Red
    exit 1
}

# ── Select projects to build ──────────────────────────────────────────────────
$toBuild = switch ($Target) {
    "All"            { $allTargets }
    "Extensions"     { $allTargets | Where-Object { $_.Group -eq "Extensions" } }
    default          { $allTargets | Where-Object { $_.Group -eq $Target -or $_.Label -eq $Target } }
}

# ── Logging ───────────────────────────────────────────────────────────────────
$LogFile = "build.log"
"" | Set-Content $LogFile

function Log {
    param([string]$Message)
    Write-Host $Message
    Add-Content $LogFile $Message
}

# ── Build ─────────────────────────────────────────────────────────────────────
$script:results = [System.Collections.Generic.List[PSCustomObject]]::new()

function Build-Project {
    param([string]$Label, [string]$Path)

    Log ""
    Log "Building $Label..."

    $output = dotnet build $Path -c $Configuration --nologo -v quiet 2>&1
    $output | ForEach-Object { Add-Content $LogFile $_ }
    if ($LASTEXITCODE -eq 0) {
        $script:results.Add([PSCustomObject]@{ Project = $Label; Result = "OK" })
    } else {
        $output | ForEach-Object { Write-Host $_ }
        $script:results.Add([PSCustomObject]@{ Project = $Label; Result = "FAILED" })
    }
}

Log "Target: $Target | Configuration: $Configuration"

foreach ($t in $toBuild) {
    Build-Project $t.Label $t.Path
}

# ── Summary ───────────────────────────────────────────────────────────────────
Log ""
Log "=== Summary ==="
$summary = $script:results | Format-Table -Property Project, Result -AutoSize | Out-String
Write-Host $summary
Add-Content $LogFile $summary

$failed = $script:results | Where-Object { $_.Result -ne "OK" }
if ($failed) {
    $msg = "$($failed.Count) project(s) failed to build."
    Write-Host $msg -ForegroundColor Red
    Add-Content $LogFile $msg
    exit 1
} else {
    $msg = "All projects built successfully."
    Write-Host $msg -ForegroundColor Green
    Add-Content $LogFile $msg
}
