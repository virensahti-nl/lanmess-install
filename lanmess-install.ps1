param(
    [string]$InstallDir = "$env:LOCALAPPDATA\LANMess"
)

$LogFile = "$env:TEMP\lanmess_install.log"
"Starting LANMess installation..." | Out-File -FilePath $LogFile -Encoding utf8

function Log([string]$msg) {
    $msg | Out-File -FilePath $LogFile -Append
}

# ---------- 1. Find or install Python ----------
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) { $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue }

if (-not $pythonCmd) {
    Log "Python not found. Attempting user‑scope installation via winget..."
    # --scope user tries to avoid admin prompts; if the Python installer
    # does not support user scope, winget will fail – we then fall back to the embeddable package.
    winget install --id Python.Python.3 --exact --source winget `
        --scope user --accept-package-agreements --accept-source-agreements --silent *>> $LogFile

    # Refresh PATH in the current session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        Log "ERROR: Python installation failed (winget user scope not supported)."
        exit 1
    }
}
$pythonExe = $pythonCmd.Source

# ---------- 2. Install LANMess for the current user ----------
Log "Installing LANMess..."
& $pythonExe -m ensurepip --upgrade *>> $LogFile
& $pythonExe -m pip install --user --upgrade lanmess *>> $LogFile
if ($LASTEXITCODE -ne 0) {
    Log "ERROR: pip install lanmess failed with exit code $LASTEXITCODE."
    exit 1
}

# ---------- 3. Get correct USER‑level paths ----------
# Use the 'nt_user' scheme – this matches where pip --user actually places files.
$scriptsDir = (& $pythonExe -c "import sysconfig; print(sysconfig.get_path('scripts', scheme='nt_user'))").Trim()
$siteDir    = (& $pythonExe -c "import site; print(site.getusersitepackages())").Trim()

Log "Scripts Dir: $scriptsDir"
Log "Site Dir:    $siteDir"

# ---------- 4. Create the batch launcher ----------
$BatFile = Join-Path $InstallDir "LANMess.bat"
$lanmessExe = Join-Path $scriptsDir "lanmess.exe"

if (Test-Path $lanmessExe) {
    # pip generated an .exe – use it directly.
    $BatContent = @"
@echo off
title LANMess
"$lanmessExe"
if %ERRORLEVEL% neq 0 pause
"@
} else {
    # Fallback: run the module with Python and point PYTHONPATH at the user site‑packages.
    $BatContent = @"
@echo off
title LANMess
set PYTHONPATH=%PYTHONPATH%;$siteDir
"$pythonExe" -m lanmess
if %ERRORLEVEL% neq 0 pause
"@
}

Set-Content -Path $BatFile -Value $BatContent -Encoding ASCII

if (-not (Test-Path $BatFile)) {
    Log "ERROR: Failed to create $BatFile."
    exit 1
}

Log "Installation completed successfully!"
exit 0                                                                                                                    