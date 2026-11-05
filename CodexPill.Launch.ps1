#requires -Version 5.1
<#
  Start Codex Pill without attaching a console to the widget process.
  This bootstrap exits immediately after launching the independent child.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$launchExitCode = 0
$launchedProcess = $null
try {
    if ($env:OS -ne 'Windows_NT') { throw 'Codex Pill est une application Windows.' }
    $mainScriptPath = Join-Path $PSScriptRoot 'codex-pill.ps1'
    $windowsPowerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not [IO.File]::Exists($mainScriptPath)) {
        throw 'codex-pill.ps1 est introuvable. Extrais tout le ZIP dans le meme dossier.'
    }
    if (-not [IO.File]::Exists($windowsPowerShellPath)) {
        throw 'Windows PowerShell est introuvable sur cet ordinateur.'
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $windowsPowerShellPath
    $startInfo.WorkingDirectory = $PSScriptRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    # Windows file paths cannot contain a double quote. Quoting the full path
    # preserves spaces and apostrophes without passing source text to -Command.
    $startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "' + $mainScriptPath + '"'
    $launchedProcess = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $launchedProcess) { throw 'Le processus Codex Pill n''a pas pu etre cree.' }
} catch {
    $launchExitCode = 1
    $errorMessage = "Le lancement de Codex Pill a echoue.`r`n`r`n" + $_.Exception.Message + "`r`n`r`nLance Diagnostic Codex Pill.cmd pour afficher les details."
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($errorMessage, 'Codex Pill', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error)
    } catch {
        [Console]::Error.WriteLine($errorMessage)
    }
} finally {
    # Disposing this handle does not stop the independent widget process.
    if ($null -ne $launchedProcess) { $launchedProcess.Dispose() }
}
exit $launchExitCode
