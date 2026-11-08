#Requires -Version 5.1
<#
.SYNOPSIS
    LANMess Windows Installer
.DESCRIPTION
    Installs LANMess (local encrypted terminal messenger) on Windows.
    Handles Python detection, winget install, pip setup, PATH configuration,
    app icon download, and desktop/start-menu shortcuts.
.NOTES
    Run with:
        irm https://raw.githubusercontent.com/virensahti-nl/lanmess-install/main/windows.ps1 | iex
    Or:
        powershell -ExecutionPolicy Bypass -File windows.ps1
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$ScriptVersion         = '1.3.0'

# =====================================================================
#                              CONFIG
# =====================================================================
$IconUrls = @(
    'https://raw.githubusercontent.com/virensahti-nl/lanmess-install/refs/heads/main/LANMess.png',
    'https://raw.githubusercontent.com/virensahti-nl/lanmess-install/main/LANMess.png'
)
$IconDir = Join-Path $env:LOCALAPPDATA 'LANMess'
$IconPng = Join-Path $IconDir 'LANMess.png'
$IconIco = Join-Path $IconDir 'LANMess.ico'

# =====================================================================
#                              HELPERS
# =====================================================================
function Write-Step($msg) { Write-Host ''; Write-Host "  ==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "      [OK]  $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "      [!!]  $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "      [XX]  $msg" -ForegroundColor Red }
function Write-Info($msg) { Write-Host "            $msg" -ForegroundColor DarkGray }

# -- Verify a path points to a real Python 3 interpreter --
function Test-RealPython($exePath) {
    if ([string]::IsNullOrWhiteSpace($exePath)) { return $false }
    if (-not (Test-Path -LiteralPath $exePath)) { return $false }

    # 0-byte files are Windows Store alias stubs
    try {
        $fi = Get-Item -LiteralPath $exePath -ErrorAction Stop
        if ($fi.Length -eq 0) { return $false }
        # Small files in WindowsApps are also stubs
        if ($exePath -like '*\WindowsApps\*' -and $fi.Length -lt 1000) { return $false }
    } catch { return $false }

    try {
        $out = & $exePath -c "import sys; print(sys.version_info[0])" 2>$null
        return ($LASTEXITCODE -eq 0 -and "$out".Trim() -eq '3')
    } catch { return $false }
}

# -- Locate a working Python 3 --
function Find-Python {
    foreach ($name in @('python', 'python3')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and (Test-RealPython $cmd.Source)) { return $cmd.Source }
    }
    # py launcher fallback
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        try {
            $real = (& $py.Source -c "import sys; print(sys.executable)" 2>$null) | Out-String
            $real = $real.Trim()
            if ($LASTEXITCODE -eq 0 -and (Test-RealPython $real)) { return $real }
        } catch { }
    }
    return $null
}

# -- PATH helpers (exact-match, case-insensitive, dedupe) --
function Split-PathList($pathString) {
    if ([string]::IsNullOrEmpty($pathString)) { return @() }
    return @($pathString -split ';' | Where-Object { $_ -and $_.Trim() })
}
function Normalize-Path($p) {
    return $p.Trim().TrimEnd('\', '/').ToLower()
}
function Test-DirInPathList($dir, $pathList) {
    $target = Normalize-Path $dir
    foreach ($p in $pathList) {
        if ((Normalize-Path $p) -eq $target) { return $true }
    }
    return $false
}
function Add-ToSessionPath($dir) {
    $dir = $dir.TrimEnd('\')
    if ([string]::IsNullOrEmpty($env:Path)) {
        $env:Path = $dir
        return $true
    }
    if (Test-DirInPathList $dir (Split-PathList $env:Path)) { return $false }
    $env:Path = $env:Path.TrimEnd(';') + ';' + $dir
    return $true
}
function Add-ToUserPath($dir) {
    $dir = $dir.TrimEnd('\')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (Test-DirInPathList $dir (Split-PathList $userPath)) { return $false }
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
        $dir
    } else {
        $userPath.TrimEnd(';') + ';' + $dir
    }
    if ($newPath.Length -gt 2047) {
        Write-Warn 'User PATH is very long — Windows may truncate it. Consider cleaning it up.'
    }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    return $true
}

# -- Convert PNG -> ICO (needed because .lnk does not accept PNG) --
function Convert-PngToIco($pngPath, $icoPath) {
    $img = $null; $bmp = $null; $g = $null; $icon = $null; $stream = $null
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $img = [System.Drawing.Image]::FromFile($pngPath)
        $size = 256
        $bmp = New-Object System.Drawing.Bitmap $size, $size
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($img, 0, 0, $size, $size)

        $hicon = $bmp.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($hicon)

        $stream = [System.IO.File]::Create($icoPath)
        $icon.Save($stream)
        return $true
    } catch {
        Write-Warn "Icon conversion failed: $_"
        return $false
    } finally {
        if ($stream) { try { $stream.Close() }   catch {} }
        if ($icon)   { try { $icon.Dispose() }   catch {} }
        if ($g)      { try { $g.Dispose() }      catch {} }
        if ($bmp)    { try { $bmp.Dispose() }    catch {} }
        if ($img)    { try { $img.Dispose() }    catch {} }
    }
}

# -- Download the app icon and convert it to ICO --
function Get-AppIcon {
    try {
        if (-not (Test-Path -LiteralPath $IconDir)) {
            New-Item -ItemType Directory -Path $IconDir -Force | Out-Null
        }

        # Download PNG if missing or obviously broken
        if (-not (Test-Path -LiteralPath $IconPng) -or (Get-Item $IconPng).Length -lt 200) {
            $downloaded = $false
            foreach ($url in $IconUrls) {
                try {
                    Write-Info "Downloading icon from $url"
                    Invoke-WebRequest -Uri $url -OutFile $IconPng -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
                    if ((Get-Item $IconPng).Length -gt 200) { $downloaded = $true; break }
                } catch {
                    Write-Info "  ...failed, trying next URL"
                }
            }
            if (-not $downloaded) { throw 'Could not download icon from any URL' }
        }

        # Convert to ICO once
        if (-not (Test-Path -LiteralPath $IconIco)) {
            if (-not (Convert-PngToIco $IconPng $IconIco)) { return $null }
        }
        return $IconIco
    } catch {
        Write-Warn "Could not prepare icon: $_"
        return $null
    }
}

# -- Create a .lnk shortcut with optional custom icon --
function New-AppShortcut($targetPath, $shortcutPath, $iconPath, $description) {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $sc  = $wsh.CreateShortcut($shortcutPath)
        $sc.TargetPath       = $targetPath
        $sc.WorkingDirectory = Split-Path $targetPath -Parent
        $sc.Description      = $description
        if ($iconPath -and (Test-Path -LiteralPath $iconPath)) {
            $sc.IconLocation = "$iconPath,0"
        } else {
            $sc.IconLocation = "$targetPath,0"
        }
        $sc.Save()
        return $true
    } catch {
        Write-Warn "Shortcut creation failed: $_"
        return $false
    }
}

# =====================================================================
#                            MAIN INSTALLER
# =====================================================================
function Install-LANMess {
    Write-Host ''
    Write-Host '  ========================================================' -ForegroundColor Yellow
    Write-Host "           L A N M e s s  Installer   v$ScriptVersion" -ForegroundColor Yellow
    Write-Host '  ========================================================' -ForegroundColor Yellow
    Write-Host '  Local encrypted terminal messenger' -ForegroundColor DarkGray
    Write-Host ''

    # ---- 1. Find or install Python ----
    Write-Step 'Checking for Python 3...'
    $pythonExe = Find-Python

    if (-not $pythonExe) {
        Write-Warn 'Python 3 not found — attempting automatic install via winget...'

        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Write-Fail 'winget is not available on this system.'
            Write-Host ''
            Write-Host '  Install Python manually:' -ForegroundColor Yellow
            Write-Host '    1. https://www.python.org/downloads/' -ForegroundColor Gray
            Write-Host '    2. Download the latest Python 3 installer' -ForegroundColor Gray
            Write-Host '    3. IMPORTANT: tick "Add python.exe to PATH"' -ForegroundColor Gray
            Write-Host '    4. Re-run this script' -ForegroundColor Gray
            Write-Host ''
            return $false
        }

        try {
            & winget install --id Python.Python.3 --exact --source winget `
                --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Host
        } catch {
            Write-Warn "winget reported: $_"
        }

        # Refresh PATH from registry
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPathNow = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = (@($machinePath, $userPathNow) | Where-Object { $_ }) -join ';'

        Write-Info 'Waiting for Python to become available (up to 40s)...'
        for ($i = 0; $i -lt 20 -and -not $pythonExe; $i++) {
            Start-Sleep -Seconds 2
            $pythonExe = Find-Python
        }

        if (-not $pythonExe) {
            Write-Fail 'Python install could not be verified.'
            Write-Host ''
            Write-Host '  Please close this window, open a NEW PowerShell,' -ForegroundColor Yellow
            Write-Host '  and run the installer again.' -ForegroundColor Yellow
            Write-Host ''
            return $false
        }
    }

    Write-OK "Python: $pythonExe"

    # ---- 2. Upgrade pip tooling ----
    Write-Step 'Upgrading pip...'
    try { & $pythonExe -m ensurepip --upgrade 2>&1 | Out-Null } catch {}
    try {
        & $pythonExe -m pip install --upgrade pip setuptools wheel `
            --quiet --disable-pip-version-check 2>&1 | Out-Host
        Write-OK 'pip is up to date'
    } catch {
        Write-Warn 'pip upgrade had a minor issue — continuing.'
    }

    # ---- 3. Install lanmess ----
    Write-Step 'Installing LANMess...'
    $existing = & $pythonExe -m pip show lanmess 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing) {
        Write-Info 'LANMess is already installed — upgrading to latest version.'
    }

    try {
        & $pythonExe -m pip install --upgrade lanmess --disable-pip-version-check
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'Standard install failed — retrying with --user flag...'
            & $pythonExe -m pip install --upgrade --user lanmess --disable-pip-version-check
            if ($LASTEXITCODE -ne 0) { throw "pip exited with code $LASTEXITCODE" }
        }
    } catch {
        Write-Fail "Failed to install LANMess: $_"
        return $false
    }

    $verify = & $pythonExe -m pip show lanmess 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $verify) {
        Write-Fail 'LANMess was not registered by pip — installation failed.'
        return $false
    }
    Write-OK 'LANMess package installed'

    # ---- 4. Locate lanmess.exe ----
    Write-Step "Setting up the 'lanmess' command..."

    $scriptDirs = New-Object System.Collections.Generic.List[string]
    foreach ($scheme in @('scripts', 'nt_user')) {
        try {
            $p = (& $pythonExe -c "import sysconfig; print(sysconfig.get_path('$scheme'))" 2>$null) | Out-String
            $p = $p.Trim()
            if ($p -and -not [string]::IsNullOrWhiteSpace($p)) { $scriptDirs.Add($p) }
        } catch { }
    }
    $appDataPython = Join-Path $env:APPDATA 'Python'
    if (Test-Path $appDataPython) {
        Get-ChildItem $appDataPython -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue |
            ForEach-Object { $scriptDirs.Add((Join-Path $_.FullName 'Scripts')) }
    }

    $lanmessExe = $null
    foreach ($dir in ($scriptDirs | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        $candidate = Join-Path $dir 'lanmess.exe'
        if (Test-Path -LiteralPath $candidate) {
            $lanmessExe = $candidate
            if (Add-ToSessionPath $dir) { Write-OK "Added to session PATH: $dir" }
            else                        { Write-OK "Already in session PATH: $dir" }
            if (Add-ToUserPath $dir)    { Write-OK "Added to user PATH:    $dir" }
            else                        { Write-OK "Already in user PATH:  $dir" }
            break
        }
    }

    if (-not $lanmessExe) {
        $cmd = Get-Command lanmess -ErrorAction SilentlyContinue
        if ($cmd) { $lanmessExe = $cmd.Source }
    }

    if (-not $lanmessExe) {
        Write-Warn 'Could not locate lanmess.exe in any Scripts folder.'
        Write-Host ''
        Write-Host '  Finish setup manually:' -ForegroundColor Yellow
        Write-Host "    `$dir = & '$pythonExe' -c `"import sysconfig; print(sysconfig.get_path('scripts'))`"" -ForegroundColor Gray
        Write-Host "    `$env:Path += `";`$dir`"" -ForegroundColor Gray
        Write-Host ''
        return $false
    }
    Write-OK "lanmess.exe: $lanmessExe"

    # ---- 5. Download app icon ----
    Write-Step 'Preparing app icon...'
    $iconPath = Get-AppIcon
    if ($iconPath) { Write-OK "Icon ready: $iconPath" }
    else           { Write-Warn 'Proceeding without custom icon (using exe icon).' }

    # ---- 6. Success message ----
    Write-Host ''
    Write-Host '  ========================================================' -ForegroundColor Green
    Write-Host '             Installation Complete!' -ForegroundColor Green
    Write-Host '  ========================================================' -ForegroundColor Green
    Write-Host ''
    Write-Host '  To launch LANMess:' -ForegroundColor White
    Write-Host '    1. Close this window and open a NEW PowerShell' -ForegroundColor Gray
    Write-Host '       (so the updated PATH is picked up)' -ForegroundColor Gray
    Write-Host '    2. Type:  lanmess' -ForegroundColor Yellow
    Write-Host ''

    # ---- 7. Optional shortcuts ----
    if ([Environment]::UserInteractive) {
        try {
            $answer = Read-Host '  Create a desktop shortcut? (y/n)'
        } catch { $answer = 'n' }

        if ($answer -match '^\s*[yY]') {
            $desktop = [Environment]::GetFolderPath('Desktop')
            $lnk     = Join-Path $desktop 'LANMess.lnk'
            if (New-AppShortcut $lanmessExe $lnk $iconPath 'LANMess — Local Encrypted Terminal Messenger') {
                Write-OK "Desktop shortcut created: $lnk"
            }
        }

        try {
            $answer2 = Read-Host '  Add to Start Menu? (y/n)'
        } catch { $answer2 = 'n' }

        if ($answer2 -match '^\s*[yY]') {
            $startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'LANMess.lnk'
            if (New-AppShortcut $lanmessExe $startMenu $iconPath 'LANMess — Local Encrypted Terminal Messenger') {
                Write-OK "Start Menu shortcut created: $startMenu"
            }
        }
    }

    Write-Host ''
    Write-Host '  Thanks for installing LANMess!' -ForegroundColor Yellow
    Write-Host ''
    return $true
}

# =====================================================================
#                              EXECUTE
# =====================================================================
if ($env:OS -ne 'Windows_NT') {
    Write-Host ''
    Write-Host '  [XX] This installer is designed for Windows only.' -ForegroundColor Red
    Write-Host ''
    return
}

try {
    $success = Install-LANMess
    if (-not $success) {
        Write-Host '  Installation did not complete successfully.' -ForegroundColor Red
        Write-Host ''
    }
} catch {
    Write-Host ''
    Write-Host "  [XX] Unexpected error: $_" -ForegroundColor Red
    Write-Host "       At line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
    Write-Host "       Command: $($_.InvocationInfo.MyCommand)" -ForegroundColor DarkGray
    Write-Host ''
}
