if (!(Get-Command python -ErrorAction SilentlyContinue)) {
    winget install Python.Python.3.11 --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

python -m ensurepip --upgrade
python -m pip install --upgrade pip
python -m pip install lanmess

$pythonPath = (Get-Command python).Source
$scriptsPath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($pythonPath), "Scripts")
$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$scriptsPath*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$userPath;$scriptsPath", "User")
}

$response = Read-Host "Do you want to create a desktop shortcut for lanmess? (y/n)"
if ($response -eq 'y') {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $targetPath = "$scriptsPath\lanmess.exe"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $WScriptShell.CreateShortcut("$desktop\lanmess.lnk")
    $shortcut.TargetPath = $targetPath
    $shortcut.Save()
}
