# --- 1. Detect Python (python or python3) ---
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
}

# --- 2. Install Python if missing ---
if (-not $pythonCmd) {
    Write-Host "Python not found. Installing the latest Python 3 via winget..."
    winget install --id Python.Python.3 --exact --source winget `
        --accept-package-agreements --accept-source-agreements --silent

    # Refresh PATH from registry
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        Write-Error "Python installation failed or PATH not updated. Please restart PowerShell and re-run."
        exit 1
    }
}

Write-Host "Using Python: $($pythonCmd.Source)"

# --- 3. Upgrade pip, setuptools, wheel ---
& $pythonCmd.Source -m ensurepip --upgrade
& $pythonCmd.Source -m pip install --upgrade pip setuptools wheel

# --- 4. Install lanmess ---
& $pythonCmd.Source -m pip install --upgrade lanmess

# --- 5. Locate the user Scripts folder reliably ---
$scriptsDir = & $pythonCmd.Source -c "import sysconfig; print(sysconfig.get_path('scripts'))"

if (-not (Test-Path $scriptsDir)) {
    Write-Warning "Scripts directory not found: $scriptsDir"
}

# --- 6. Update PATH for the current session ---
if ($env:Path -notlike "*$scriptsDir*") {
    $env:Path += ";$scriptsDir"
    Write-Host "Added $scriptsDir to the current session PATH."
}

# --- 7. Update the user PATH permanently (no duplicates) ---
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$scriptsDir*") {
    [System.Environment]::SetEnvironmentVariable("Path", "$userPath;$scriptsDir", "User")
    Write-Host "Added $scriptsDir to the permanent user PATH."
} else {
    Write-Host "$scriptsDir is already in the permanent user PATH."
}

# --- 8. Find the lanmess executable ---
$lanmessExe = Join-Path $scriptsDir "lanmess.exe"
if (-not (Test-Path $lanmessExe)) {
    $lanmessExe = (Get-Command lanmess -ErrorAction SilentlyContinue).Source
}
if (-not $lanmessExe) {
    Write-Error "lanmess executable not found. Installation may have failed."
    exit 1
}
Write-Host "lanmess executable: $lanmessExe"

# --- 9. Optional desktop shortcut ---
$response = Read-Host "Create a desktop shortcut for lanmess? (y/n) (yes or no)"
if ($response -match '^[yY]') {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "lanmess.lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $lanmessExe
    $shortcut.WorkingDirectory = Split-Path $lanmessExe -Parent
    $shortcut.Save()
    Write-Host "Shortcut created at $shortcutPath"
}
