if (!(Get-Command python -ErrorAction SilentlyContinue)) {
    winget install Python.Python.3.11 --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

python -m ensurepip --upgrade
python -m pip install --upgrade pip
python -m pip install lanmess

$userScripts = [System.IO.Path]::Combine($env:APPDATA, "Python", "Python311", "Scripts")
if (Test-Path $userScripts) {
    $env:PATH += ";$userScripts"
}
[System.Environment]::SetEnvironmentVariable("PATH", [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";$userScripts", "User")

$lanmessCmd = Get-Command lanmess -ErrorAction SilentlyContinue
if ($lanmessCmd) {
    $targetPath = $lanmessCmd.Source
} else {
    $targetPath = (where.exe lanmess 2>$null | Select-Object -First 1)
}

$response = Read-Host "Do you want to create a desktop shortcut for lanmess? (y/n)"
if ($response -eq 'y' -and $targetPath) {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $WScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $WScriptShell.CreateShortcut("$desktop\lanmess.lnk")
    $shortcut.TargetPath = $targetPath
    $shortcut.Save()
}
