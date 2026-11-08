# LANMess Windows Installer
# Run with: irm https://raw.githubusercontent.com/virensahti-nl/lanmess-install/main/windows.ps1 | iex
#
# If you saved this file and get an "execution policy" error, run:
#   powershell -ExecutionPolicy Bypass -File windows.ps1

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ---------- Pretty output helpers ----------
function Write-Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    [OK]  $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    [!!]  $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "    [XX]  $msg" -ForegroundColor Red }

# ---------- Verify a Python path is a real interpreter (not the Store stub) ----------
function Test-RealPython($exePath) {
    if ([string]::IsNullOrWhiteSpace($exePath)) { return $false }
    if (-not (Test-Path $exePath))              { return $false }
    try {
        $out = & $exePath -c "import sys; print(sys.version_info[0])" 2>$null
        return ($LASTEXITCODE -eq 0 -and "$out".Trim() -eq '3')
    } catch { return $false }
}

# ---------- Find a working Python 3 ----------
function Find-Python {
    foreach ($name in @('python', 'python3')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and (Test-RealPython $cmd.Source)) { return $cmd.Source }
    }
    # py launcher fallback
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        try {
            $real = & $py.Source -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and (Test-RealPython $real)) { return $real.Trim() }
        } catch {}
    }
    return $null
}

# ---------- PATH helpers (normalize, dedupe, exact match) ----------
function Get-NormalizedPathList($pathString) {
    if ([string]::IsNullOrEmpty($pathString)) { return @() }
    return @($pathString -split ';' |
        Where-Object { $_ -and $_.Trim() } |
        ForEach-Object { $_.Trim().TrimEnd('\').ToLower() })
}

function Test-DirInPathString($dir, $pathString) {
    $target = $dir.TrimEnd('\').ToLower()
    return ((Get-NormalizedPathList $pathString) -contains $target)
}

function Add-ToSessionPath($dir) {
    if (-not (Test-DirInPathString $dir $env:Path)) {
        $env:Path = ($env:Path.TrimEnd(';') + ';' + $dir.TrimEnd('\')).TrimStart(';')
        return $true
    }
    return $false
}

function Add-ToUserPath($dir) {
    $dir = $dir.TrimEnd('\')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (Test-DirInPathString $dir $userPath) { return $false }
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
        $dir
    } else {
        $userPath.TrimEnd(';') + ';' + $dir
    }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    return $true
}

# ================================================================
#                        WELCOME BANNER
# ================================================================
Write-Host ""
Write-Host "  ===================================================" -ForegroundColor Yellow
Write-Host "              L A N M e s s  Installer" -ForegroundColor Yellow
Write-Host "  ===================================================" -ForegroundColor Yellow
Write-Host "  This will install LANMess and its Python dependency." -ForegroundColor DarkGray
Write-Host ""

# ================================================================
#                    1. FIND OR INSTALL PYTHON
# ================================================================
Write-Step "Looking for Python 3..."
$pythonExe = Find-Python

if (-not $pythonExe) {
    Write-Warn "Python 3 not found. Attempting automatic install via winget..."

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Fail "winget is not available on this system."
        Write-Host ""
        Write-Host "  Please install Python manually:" -ForegroundColor Yellow
        Write-Host "    1. Go to https://www.python.org/downloads/" -ForegroundColor Gray
        Write-Host "    2. Download the latest Python 3 installer" -ForegroundColor Gray
        Write-Host "    3. IMPORTANT: tick 'Add python.exe to PATH' during install" -ForegroundColor Gray
        Write-Host "    4. Re-run this script" -ForegroundColor Gray
        Write-Host ""
        return
    }

    try {
        & winget install --id Python.Python.3 --exact --source winget `
            --accept-package-agreements --accept-source-agreements --silent `
            --disable-interactivity 2>&1 | Out-Null
    } catch {
        Write-Warn "winget reported an issue: $_"
    }

    # Refresh PATH from registry so this session can see the new Python
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPathNow = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machinePath, $userPathNow) | Where-Object { $_ }) -join ';'

    # Poll for up to ~30 s until Python becomes usable
    Write-Host "    Waiting for Python to become available..." -ForegroundColor DarkGray
    for ($i = 0; $i -lt 15 -and -not $pythonExe; $i++) {
        Start-Sleep -Seconds 2
        $pythonExe = Find-Python
    }

    if (-not $pythonExe) {
        Write-Fail "Python install could not be verified."
        Write-Host ""
        Write-Host "  Please close this window, open a NEW PowerShell," -ForegroundColor Yellow
        Write-Host "  and run the installer again." -ForegroundColor Yellow
        Write-Host ""
        return
    }
}

Write-OK "Using Python: $pythonExe"

# ================================================================
#                     2. UPGRADE PIP TOOLS
# ================================================================
Write-Step "Upgrading pip..."
try {
    & $pythonExe -m ensurepip --upgrade 2>$null | Out-Null
    & $pythonExe -m pip install --upgrade pip setuptools wheel `
        --quiet --disable-pip-version-check 2>&1 | Out-Null
    Write-OK "pip is up to date"
} catch {
    Write-Warn "pip upgrade had a minor issue — continuing anyway."
}

# ================================================================
#                      3. INSTALL LANMESS
# ================================================================
Write-Step "Installing LANMess..."
try {
    & $pythonExe -m pip install --upgrade lanmess --disable-pip-version-check
    if ($LASTEXITCODE -ne 0) { throw "pip exited with code $LASTEXITCODE" }
} catch {
    Write-Fail "Failed to install LANMess: $_"
    return
}

# Verify the package really registered
$installed = & $pythonExe -m pip show lanmess 2>$null
if (-not $installed) {
    Write-Fail "LANMess was not registered by pip — installation failed."
    return
}
Write-OK "LANMess package installed"

# ================================================================
#                 4. LOCATE lanmess.exe AND PATCH PATH
# ================================================================
Write-Step "Setting up the 'lanmess' command..."

# Ask Python for BOTH the default and the per-user Scripts directories,
# because pip may have used either depending on write permissions.
$scriptDirs = New-Object System.Collections.Generic.List[string]
foreach ($scheme in @('scripts', 'nt_user')) {
    try {
        $p = & $pythonExe -c "import sysconfig; print(sysconfig.get_path('$scheme'))" 2>$null
        if ($p) { $scriptDirs.Add($p.Trim()) }
    } catch {}
}
# Extra safety net: %APPDATA%\Python\Python3*\Scripts
$appDataPython = Join-Path $env:APPDATA 'Python'
if (Test-Path $appDataPython) {
    Get-ChildItem $appDataPython -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue |
        ForEach-Object { $scriptDirs.Add((Join-Path $_.FullName 'Scripts')) }
}

$lanmessExe = $null
foreach ($dir in ($scriptDirs | Select-Object -Unique)) {
    if ([string]::IsNullOrWhiteSpace($dir)) { continue }
    $candidate = Join-Path $dir 'lanmess.exe'
    if (Test-Path $candidate) {
        $lanmessExe = $candidate

        # Patch current session PATH
        if (Add-ToSessionPath $dir) { Write-OK "Added to session PATH: $dir" }
        else                        { Write-OK "Already in session PATH: $dir" }

        # Patch permanent user PATH
        if (Add-ToUserPath $dir)    { Write-OK "Added to permanent user PATH: $dir" }
        else                        { Write-OK "Already in permanent user PATH: $dir" }
        break
    }
}

if (-not $lanmessExe) {
    Write-Warn "Could not locate lanmess.exe in any Scripts folder."
    Write-Host ""
    Write-Host "  Try running these commands manually to finish setup:" -ForegroundColor Yellow
    Write-Host "    `$dir = & '$pythonExe' -c `"import sysconfig; print(sysconfig.get_path('scripts'))`"" -ForegroundColor Gray
    Write-Host "    [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';' + `$dir, 'User')" -ForegroundColor Gray
    Write-Host ""
    return
}

Write-OK "Found lanmess at: $lanmessExe"

# ================================================================
#                      5. FINAL INSTRUCTIONS
# ================================================================
Write-Host ""
Write-Host "  ===================================================" -ForegroundColor Green
Write-Host "              Installation Complete!" -ForegroundColor Green
Write-Host "  ===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  How to launch LANMess:" -ForegroundColor White
Write-Host "    1. Close this window and open a NEW PowerShell" -ForegroundColor Gray
Write-Host "       (so it picks up the updated PATH)" -ForegroundColor Gray
Write-Host "    2. Type:  lanmess" -ForegroundColor Yellow
Write-Host ""

# ================================================================
#                   6. OPTIONAL DESKTOP SHORTCUT
# ================================================================
if ([Environment]::UserInteractive) {
    $response = Read-Host "  Create a desktop shortcut? (y/n)"
    if ($response -match '^\s*[yY]') {
        try {
            $desktop      = [Environment]::GetFolderPath('Desktop')
            $shortcutPath = Join-Path $desktop 'LANMess.lnk'
            $wsh          = New-Object -ComObject WScript.Shell
            $shortcut     = $wsh.CreateShortcut($shortcutPath)
            $shortcut.TargetPath       = $lanmessExe
            $shortcut.WorkingDirectory = Split-Path $lanmessExe -Parent
            $shortcut.IconLocation     = "$lanmessExe,0"
            $shortcut.Description      = 'LANMess - Local Encrypted Terminal Messenger'
            $shortcut.Save()
            Write-OK "Shortcut created: $shortcutPath"
        } catch {
            Write-Warn "Could not create shortcut: $_"
        }
    }
}

Write-Host ""
Write-Host "  Thanks for installing LANMess!" -ForegroundColor Yellow
Write-Host ""
