# Sync.ps1 - Manage all PhotoDewey git repositories
#
# Syncs all repos: clones any that are missing, pulls and pushes all others.
# Extension repos are discovered automatically via the GitHub CLI.
# If there are uncommitted changes and no -Message was given, you will be prompted once.
# Conflicts are reported per repo and that repo is skipped.
#
# Folder structure:
#   Application/                    (Source-Applications)
#   WebShop/
#   Extensions/<Name>/Source/       (Source-Extension-<Name>)
#   Extensions/<Name>/Public/       (Extension-<Name>)
#
# Usage:
#   .\Sync.ps1
#   .\Sync.ps1 -Message "My commit message"

param(
    [string]$Message = ""
)

function Sync-Repo {
    param([string]$Url, [string]$Dir)
    if (Test-Path "$Dir\.git") {
        Write-Host "Pulling $Dir..."
        git -C $Dir pull
    } else {
        Write-Host "Cloning $Url..."
        git clone $Url $Dir
    }
}

function Push-Repo {
    param([string]$Dir, [string]$Label)

    if (-not (Test-Path "$Dir\.git")) { return }

    # Stage and commit any uncommitted changes
    $status = git -C $Dir status --porcelain
    if ($status) {
        if (-not $Message) {
            $pendingCount = @($status).Count
            Write-Host ""
            $Message = Read-Host "$Label has $pendingCount pending change(s). Commit message"
        }
        git -C $Dir add -A
        git -C $Dir commit -m $Message
    }

    # Pull and detect conflicts
    $pullOutput = git -C $Dir pull 2>&1
    if ($LASTEXITCODE -ne 0) {
        $conflicts = git -C $Dir diff --name-only --diff-filter=U
        if ($conflicts) {
            Write-Warning "$Label - CONFLICTS in: $($conflicts -join ', '). Resolve manually and re-run."
        } else {
            Write-Warning "$Label - Pull failed: $pullOutput"
        }
        return
    }

    # Count commits ahead of remote
    $ahead = git -C $Dir rev-list --count "@{u}..HEAD" 2>$null
    if ($LASTEXITCODE -ne 0) { $ahead = 0 }

    Write-Host "$Label - $ahead commit(s) to push"

    if ($ahead -gt 0) {
        git -C $Dir push
    }
}

function Sync-Extensions {
    if (-not (Test-Path "Extensions")) {
        New-Item -ItemType Directory -Path "Extensions" | Out-Null
    }

    $names = gh repo list PhotoDewey --limit 1000 --json name -q '.[].name' |
        Where-Object { $_ -match '^Extension-' } |
        ForEach-Object { $_ -replace '^Extension-', '' }

    foreach ($name in $names) {
        $extDir = "Extensions\$name"
        if (-not (Test-Path $extDir)) { New-Item -ItemType Directory -Path $extDir | Out-Null }

        $sourceDir = "$extDir\Source"
        if (-not (Test-Path $sourceDir)) { New-Item -ItemType Directory -Path $sourceDir | Out-Null }

        $publicDir = "$extDir\Public"
        if (-not (Test-Path $publicDir)) { New-Item -ItemType Directory -Path $publicDir | Out-Null }

        Sync-Repo "git@github.com:PhotoDewey/Source-Extension-$name.git" $sourceDir
        Sync-Repo "git@github.com:PhotoDewey/Extension-$name.git" $publicDir
    }
}

Write-Host ""
Write-Host "Running Sync-Repo for top-level repositories..."
Sync-Repo "git@github.com:PhotoDewey/Source-Applications.git" "Application"
Sync-Repo "git@github.com:PhotoDewey/WebShop.git" "WebShop"
Sync-Repo "git@github.com:PhotoDewey/.github.git" ".github"

Write-Host ""
Write-Host "Synchronizing the script..."
# Keep a copy of this script in .github/scripts 
$scriptsDest = ".github\scripts"
if (-not (Test-Path $scriptsDest)) { New-Item -ItemType Directory -Path $scriptsDest | Out-Null }
$destPath = "$scriptsDest\Sync.ps1"
$srcTime  = (Get-Item $PSCommandPath).LastWriteTime
$destTime = if (Test-Path $destPath) { (Get-Item $destPath).LastWriteTime } else { [datetime]::MinValue }
if ($destTime -gt $srcTime) {
    Write-Warning "A newer version of Sync.ps1 exists in .github/scripts ($destTime vs local $srcTime). Copy it locally before running."
    exit 1
} elseif ($srcTime -gt $destTime) {
    Copy-Item -Path $PSCommandPath -Destination $destPath -Force
    Write-Host ".github/scripts/Sync.ps1 updated."
}


Write-Host ""
Write-Host "Running Push-Repo for top-level repositories..."
Push-Repo "Application" "Application"
Push-Repo "WebShop"     "WebShop"
Push-Repo ".github"     ".github"

Write-Host ""
Write-Host "Running Sync-Extensions..."
Sync-Extensions

Write-Host ""
Write-Host "Running Push-Repo for extensions..."
$extensionDirs = Get-ChildItem -Path "Extensions" -Directory -ErrorAction SilentlyContinue
foreach ($ext in $extensionDirs) {
    Push-Repo "Extensions\$($ext.Name)\Source" "Extension $($ext.Name) / Source"
    Push-Repo "Extensions\$($ext.Name)\Public" "Extension $($ext.Name) / Public"
}
