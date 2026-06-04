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

$script:results = [System.Collections.Generic.List[PSCustomObject]]::new()

function Sync-Repo {
    param([string]$Url, [string]$Dir)
    if (Test-Path "$Dir\.git") {
        Write-Host "Pulling $Dir..."
        git -C $Dir pull
        $script:results.Add([PSCustomObject]@{ Repo = $Dir; Action = "Pulled" })
    } else {
        Write-Host "Cloning $Url..."
        git clone $Url $Dir
        $script:results.Add([PSCustomObject]@{ Repo = $Dir; Action = "Cloned" })
    }
}

function Push-Repo {
    param([string]$Dir, [string]$Label)

    if (-not (Test-Path "$Dir\.git")) { return }

    # Stage and commit any uncommitted changes
    $status = git -C $Dir status --porcelain
    $committed = $false
    if ($status) {
        if (-not $Message) {
            $pendingCount = @($status).Count
            Write-Host ""
            $Message = Read-Host "$Label has $pendingCount pending change(s). Commit message"
        }
        git -C $Dir add -A
        git -C $Dir commit -m $Message
        $committed = $true
    }

    # Pull and detect conflicts
    $pullOutput = git -C $Dir pull 2>&1
    if ($LASTEXITCODE -ne 0) {
        $conflicts = git -C $Dir diff --name-only --diff-filter=U
        if ($conflicts) {
            Write-Warning "$Label - CONFLICTS in: $($conflicts -join ', '). Resolve manually and re-run."
            $script:results.Add([PSCustomObject]@{ Repo = $Label; Action = "CONFLICT" })
        } else {
            Write-Warning "$Label - Pull failed: $pullOutput"
            $script:results.Add([PSCustomObject]@{ Repo = $Label; Action = "Pull failed" })
        }
        return
    }

    # Count commits ahead of remote
    $ahead = git -C $Dir rev-list --count "@{u}..HEAD" 2>$null
    if ($LASTEXITCODE -ne 0) { $ahead = 0 }

    Write-Host "$Label - $ahead commit(s) to push"

    if ($ahead -gt 0) {
        git -C $Dir push
        $action = if ($committed) { "Committed + pushed" } else { "Pushed" }
    } else {
        $action = if ($committed) { "Committed" } else { "Up to date" }
    }
    $script:results.Add([PSCustomObject]@{ Repo = $Label; Action = $action })
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
Write-Host "Synchronizing scripts to .github..."
$scriptsDest = ".github\scripts"
if (-not (Test-Path $scriptsDest)) { New-Item -ItemType Directory -Path $scriptsDest | Out-Null }

# Sync.ps1 gets a conflict check — a newer version in .github means someone updated it there and it must be copied back first
$syncSrcTime  = (Get-Item $PSCommandPath).LastWriteTime
$syncDestPath = "$scriptsDest\Sync.ps1"
$syncDestTime = if (Test-Path $syncDestPath) { (Get-Item $syncDestPath).LastWriteTime } else { [datetime]::MinValue }
if ($syncDestTime -gt $syncSrcTime) {
    Write-Warning "A newer version of Sync.ps1 exists in .github/scripts ($syncDestTime vs local $syncSrcTime). Copy it locally before running."
    exit 1
} elseif ($syncSrcTime -gt $syncDestTime) {
    Copy-Item -Path $PSCommandPath -Destination $syncDestPath -Force
    Write-Host "  Sync.ps1 updated."
}

# All other root-level scripts are copied to .github/scripts if the local copy is newer
$updatedScripts = [System.Collections.Generic.List[string]]::new()
$newScripts     = [System.Collections.Generic.List[string]]::new()

Get-ChildItem -Path "." -Filter "*.ps1" -File | Where-Object { $_.FullName -ne $PSCommandPath } | ForEach-Object {
    $destPath = "$scriptsDest\$($_.Name)"
    $isNew    = -not (Test-Path $destPath)
    $destTime = if ($isNew) { [datetime]::MinValue } else { (Get-Item $destPath).LastWriteTime }
    if ($_.LastWriteTime -gt $destTime) {
        Copy-Item -Path $_.FullName -Destination $destPath -Force
        if ($isNew) {
            $newScripts.Add($_.Name)
            Write-Host "  $($_.Name) added."
        } else {
            $updatedScripts.Add($_.Name)
            Write-Host "  $($_.Name) updated."
        }
    }
}

if ($newScripts.Count -gt 0 -or $updatedScripts.Count -gt 0) {
    $commitParts = @()
    if ($newScripts.Count -gt 0)     { $commitParts += "Add $($newScripts -join ', ')" }
    if ($updatedScripts.Count -gt 0) { $commitParts += "Update $($updatedScripts -join ', ')" }
    $commitMsg = $commitParts -join '; '

    git -C ".github" add "scripts"
    git -C ".github" commit -m $commitMsg
    Write-Host "  .github committed: $commitMsg"
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

Write-Host ""
Write-Host "=== Summary ==="
$script:results | Format-Table -Property Repo, Action -AutoSize
