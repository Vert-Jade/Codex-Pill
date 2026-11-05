#requires -Version 5.1
# Creates or updates this portable copy's desktop shortcut for the current user.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$shortcutExitCode = 0
$shellObject = $null
$linkObject = $null
try {
    if ($env:OS -ne 'Windows_NT') { throw 'Ce raccourci est destine a Windows.' }
    $launchPath = Join-Path $PSScriptRoot 'CodexPill.Launch.ps1'
    $iconPath = Join-Path $PSScriptRoot 'assets\CodexPill.ico'
    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach ($requiredPath in @($launchPath, $iconPath, $powerShellPath)) {
        if (-not [IO.File]::Exists($requiredPath)) { throw ('Fichier introuvable : ' + $requiredPath + '. Extrais tout le ZIP avant de creer le raccourci.') }
    }
    # Windows resolves the user's real Desktop, including a OneDrive redirect.
    $desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    if ([string]::IsNullOrWhiteSpace($desktopPath) -or -not [IO.Directory]::Exists($desktopPath)) {
        throw 'Le dossier Bureau de cet utilisateur est introuvable.'
    }
    $shortcutPath = Join-Path $desktopPath 'Codex Pill.lnk'
    $shellObject = New-Object -ComObject WScript.Shell
    $linkObject = $shellObject.CreateShortcut($shortcutPath)
    $linkObject.TargetPath = $powerShellPath
    $linkObject.Arguments = '-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launchPath + '"'
    $linkObject.WorkingDirectory = $PSScriptRoot
    $linkObject.IconLocation = $iconPath + ',0'
    $linkObject.WindowStyle = 7
    $linkObject.Description = 'Codex Pill - suivi des quotas'
    $linkObject.Save()
    if (-not [IO.File]::Exists($shortcutPath)) { throw 'Windows n''a pas confirme la creation du raccourci.' }
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show("Le raccourci Codex Pill est pret sur ton Bureau.`r`n`r`nIl utilise le logo du programme et demarre le widget sans fenetre de commande.`r`n`r`nConserve ce dossier a sa place. Si tu le deplaces, relance Creer raccourci bureau.cmd.", 'Codex Pill', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information)
} catch {
    $shortcutExitCode = 1
    $failureMessage = "Le raccourci n'a pas pu etre cree.`r`n`r`n" + $_.Exception.Message
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($failureMessage, 'Codex Pill', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error)
    } catch { [Console]::Error.WriteLine($failureMessage) }
} finally {
    if ($null -ne $linkObject) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($linkObject) }
    if ($null -ne $shellObject) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shellObject) }
}
exit $shortcutExitCode
