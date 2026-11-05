#requires -Version 5.1
<#
  Codex Pill control process. No network access and no broad PowerShell kill.
  Force-stop requires a live process handle, exact script argument and start time.
#>
[CmdletBinding()]
param(
    [ValidateSet('Stop', 'Diagnostic', 'StopLegacy')]
    [string]$Action = 'Diagnostic',
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'
$controlRoot = $PSScriptRoot
$mainScript = [IO.Path]::GetFullPath((Join-Path $controlRoot 'codex-pill.ps1'))
$appDirectory = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'CodexPill'
$instancePath = Join-Path $appDirectory 'instance.json'
$errorLog = Join-Path $appDirectory 'error.log'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Write-ControlMessage {
    param([string]$Message)
    if (-not $Silent) { Write-Host $Message }
}

function Write-ControlError {
    param([string]$Message)
    try {
        [void][IO.Directory]::CreateDirectory($appDirectory)
        $line = '{0} [control:{1}] {2}{3}' -f [DateTime]::Now.ToString('s'), $Action, $Message, [Environment]::NewLine
        [IO.File]::AppendAllText($errorLog, $line, [Text.UTF8Encoding]::new($true))
    } catch { }
    if (-not $Silent) { Write-Host ('ERREUR : ' + $Message) -ForegroundColor Red }
}

function Initialize-ArgumentParser {
    if ('CodexPillControl.NativeArguments' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CodexPillControl {
    public static class NativeArguments {
        [DllImport("shell32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
        private static extern IntPtr CommandLineToArgvW(string commandLine, out int argc);
        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr pointer);
        public static string[] Split(string commandLine) {
            int count;
            IntPtr block = CommandLineToArgvW(commandLine, out count);
            if (block == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
            try {
                string[] values = new string[count];
                for (int i=0; i<count; i++) {
                    values[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(block, i * IntPtr.Size));
                }
                return values;
            } finally { LocalFree(block); }
        }
    }
}
'@
}

function Get-ScriptArgument {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    Initialize-ArgumentParser
    $arguments = [CodexPillControl.NativeArguments]::Split($CommandLine)
    for ($index = 1; $index -lt ($arguments.Length - 1); $index++) {
        if ($arguments[$index] -ieq '-File') {
            $candidate = $arguments[$index + 1]
            if (-not [IO.Path]::IsPathRooted($candidate)) { return $null }
            try { return [IO.Path]::GetFullPath($candidate) } catch { return $null }
        }
    }
    return $null
}

function Test-SamePath {
    param([string]$First, [string]$Second)
    if ([string]::IsNullOrWhiteSpace($First) -or [string]::IsNullOrWhiteSpace($Second)) { return $false }
    return [string]::Equals([IO.Path]::GetFullPath($First), [IO.Path]::GetFullPath($Second), [StringComparison]::OrdinalIgnoreCase)
}

function Get-ProcessProof {
    param([int]$TargetProcessId, [string]$ExpectedScriptPath, [string]$ExpectedStartTimeUtc)
    if ($TargetProcessId -le 0 -or $TargetProcessId -eq $PID) { return $null }
    $process = $null
    try {
        # Opening the process handle first binds every later operation to this
        # process object instead of trusting a reusable PID alone.
        $process = Get-Process -Id $TargetProcessId -ErrorAction Stop
        [void]$process.Handle
        $started = $process.StartTime.ToUniversalTime()
        if ($process.HasExited) { $process.Dispose(); return $null }
        $record = Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId = {0}' -f $TargetProcessId) -ErrorAction Stop
        if ($null -eq $record -or $record.Name -ine 'powershell.exe') { $process.Dispose(); return $null }
        $actualScript = Get-ScriptArgument -CommandLine $record.CommandLine
        if (-not (Test-SamePath $actualScript $ExpectedScriptPath)) { $process.Dispose(); return $null }
        if ([IO.Path]::GetFileName($actualScript) -ine 'codex-pill.ps1') { $process.Dispose(); return $null }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedStartTimeUtc)) {
            $expected = [DateTimeOffset]::Parse($ExpectedStartTimeUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            if ([Math]::Abs(($started - $expected.UtcDateTime).TotalMilliseconds) -gt 1) { $process.Dispose(); return $null }
        }
        if ($process.HasExited) { $process.Dispose(); return $null }
        return [pscustomobject]@{ Process = $process; ProcessId = $TargetProcessId; StartTimeUtc = $started.ToString('o'); ScriptPath = $actualScript }
    } catch {
        if ($null -ne $process) { $process.Dispose() }
        return $null
    }
}

function Read-Instance {
    if (-not [IO.File]::Exists($instancePath)) { return $null }
    try {
        $instance = [IO.File]::ReadAllText($instancePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($null -eq $instance.ProcessId -or -not $instance.StartTimeUtc -or -not $instance.ScriptPath) { return $null }
        return $instance
    } catch { return $null }
}

function Stop-ProvenProcess {
    param($Proof, [bool]$StopWasSignaled)
    $process = $Proof.Process
    try {
        if ($process.HasExited) { return }
        if (-not $StopWasSignaled) { [void]$process.CloseMainWindow() }
        $graceMilliseconds = if ($StopWasSignaled) { 5000 } else { 1500 }
        if ($process.WaitForExit($graceMilliseconds)) { return }
        # Check both creation time and exact -File argument once more before the
        # fallback; keep the original handle open while checking and killing.
        $verified = Get-ProcessProof -TargetProcessId $Proof.ProcessId -ExpectedScriptPath $Proof.ScriptPath -ExpectedStartTimeUtc $Proof.StartTimeUtc
        if ($null -eq $verified) {
            if ($process.HasExited) { return }
            throw 'Le processus a change. Aucun arret force ne sera effectue.'
        }
        try {
            if (-not $process.HasExited) { $process.Kill() }
            if (-not $process.WaitForExit(2500)) { throw 'Le processus ne confirme pas sa fermeture.' }
        } finally { $verified.Process.Dispose() }
    } finally { $process.Dispose() }
}

function Get-LegacyCandidates {
    param([string]$ExactScriptPath)
    $instance = Read-Instance
    $records = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction Stop)
    foreach ($record in $records) {
        if ([int]$record.ProcessId -eq $PID) { continue }
        $candidatePath = Get-ScriptArgument $record.CommandLine
        if (-not $candidatePath -or [IO.Path]::GetFileName($candidatePath) -ine 'codex-pill.ps1') { continue }
        if ($ExactScriptPath -and -not (Test-SamePath $candidatePath $ExactScriptPath)) { continue }
        $proof = Get-ProcessProof -TargetProcessId ([int]$record.ProcessId) -ExpectedScriptPath $candidatePath
        if ($null -eq $proof) { continue }
        # The registered current version is handled by Stop, not legacy cleanup.
        if ($instance -and [int]$instance.ProcessId -eq $proof.ProcessId) {
            try {
                $registeredStart = [DateTimeOffset]::Parse($instance.StartTimeUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
                $provenStart = [DateTimeOffset]::Parse($proof.StartTimeUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
                if ([Math]::Abs(($registeredStart - $provenStart).TotalMilliseconds) -le 1) {
                    $proof.Process.Dispose()
                    continue
                }
            } catch { }
        }
        $proof
    }
}

function Invoke-Stop {
    $instance = Read-Instance
    $proof = $null
    if ($instance) {
        $proof = Get-ProcessProof -TargetProcessId ([int]$instance.ProcessId) -ExpectedScriptPath $instance.ScriptPath -ExpectedStartTimeUtc $instance.StartTimeUtc
    }
    $signaled = $false
    $event = $null
    try {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $event = [Threading.EventWaitHandle]::OpenExisting('Local\CodexPill.Stop.' + $sid)
        $signaled = $event.Set()
    } catch [Threading.WaitHandleCannotBeOpenedException] {
        # No modern instance is listening. An earlier version may still exist.
    } finally {
        if ($null -ne $event) { $event.Dispose() }
    }
    if ($proof) {
        Stop-ProvenProcess -Proof $proof -StopWasSignaled $signaled
        Write-ControlMessage 'Codex Pill est ferme.'
        return
    }
    if ($signaled) {
        Write-ControlMessage 'Demande de fermeture envoyee a Codex Pill.'
        return
    }
    # This compatibility path only accepts the exact script beside this launcher.
    # Processes from a different folder require the explicit legacy cleanup tool.
    $legacy = @(Get-LegacyCandidates -ExactScriptPath $mainScript)
    foreach ($old in $legacy) { Stop-ProvenProcess -Proof $old -StopWasSignaled $false }
    if ($legacy.Count -gt 0) { Write-ControlMessage 'Ancienne instance de ce dossier fermee.' }
    else { Write-ControlMessage 'Aucune instance de Codex Pill active dans ce dossier.' }
}

function Invoke-LegacyCleanup {
    $candidates = @(Get-LegacyCandidates)
    if ($candidates.Count -eq 0) { Write-ControlMessage 'Aucune ancienne instance trouvee.'; return }
    try {
        Write-Host 'Anciennes instances detectees (chemin exact de codex-pill.ps1) :' -ForegroundColor Cyan
        for ($index = 0; $index -lt $candidates.Count; $index++) {
            $candidate = $candidates[$index]
            Write-Host ('  {0}. PID {1} - {2}' -f ($index + 1), $candidate.ProcessId, $candidate.ScriptPath)
        }
        Write-Host ''
        $answer = Read-Host 'Numero a fermer, T pour toutes les instances affichees, Entree pour annuler'
        if ([string]::IsNullOrWhiteSpace($answer)) { return }
        $selected = @()
        if ($answer.Trim() -ieq 'T') { $selected = $candidates }
        else {
            $number = 0
            if (-not [int]::TryParse($answer, [ref]$number) -or $number -lt 1 -or $number -gt $candidates.Count) {
                throw 'Selection non valide. Aucun processus arrete.'
            }
            $selected = @($candidates[$number - 1])
        }
        foreach ($candidate in $selected) {
            Stop-ProvenProcess -Proof $candidate -StopWasSignaled $false
            Write-Host ('Instance {0} fermee.' -f $candidate.ProcessId)
        }
    } finally {
        foreach ($candidate in $candidates) { $candidate.Process.Dispose() }
    }
}

function Invoke-Diagnostic {
    Write-Host 'CODEX PILL - DIAGNOSTIC' -ForegroundColor Cyan
    Write-Host ('Dossier : {0}' -f $controlRoot)
    Write-Host ('PowerShell : {0} / {1} bits / {2}' -f $PSVersionTable.PSVersion, ([IntPtr]::Size * 8), [Threading.Thread]::CurrentThread.ApartmentState)
    Write-Host ('Parametres et erreurs : {0}' -f $appDirectory)
    $syntaxFailed = $false
    foreach ($scriptFile in Get-ChildItem -LiteralPath $controlRoot -Filter '*.ps1' -File) {
        $parseTokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$parseTokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            $syntaxFailed = $true
            foreach ($parseError in $parseErrors) {
                Write-Host ('ECHEC {0}:{1} - {2}' -f $scriptFile.Name, $parseError.Extent.StartLineNumber, $parseError.Message) -ForegroundColor Red
            }
        } else { Write-Host ('Syntaxe OK : {0}' -f $scriptFile.Name) -ForegroundColor Green }
    }
    $instance = Read-Instance
    if ($instance) {
        $proof = Get-ProcessProof -TargetProcessId ([int]$instance.ProcessId) -ExpectedScriptPath $instance.ScriptPath -ExpectedStartTimeUtc $instance.StartTimeUtc
        if ($proof) {
            Write-Host ('Instance active : PID {0} - {1}' -f $proof.ProcessId, $proof.ScriptPath)
            $proof.Process.Dispose()
        } else { Write-Host 'Ancien fichier de suivi detecte, sans processus correspondant.' }
    } else { Write-Host 'Aucune instance enregistree.' }
    if ([IO.File]::Exists($errorLog)) {
        Write-Host ''
        Write-Host 'Dernieres erreurs enregistrees :' -ForegroundColor Yellow
        Get-Content -LiteralPath $errorLog -Encoding UTF8 -Tail 20
    }
    if ($syntaxFailed) { throw 'Une erreur de syntaxe empeche le lancement.' }
    if (-not [IO.File]::Exists($mainScript)) { throw 'Le fichier codex-pill.ps1 est manquant.' }
    Write-Host ''
    Write-Host 'Verification de l''application et de ses donnees locales :' -ForegroundColor Cyan
    & $windowsPowerShell -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $mainScript -Diagnostic
    if ($LASTEXITCODE -ne 0) { throw ('Diagnostic de l''application termine avec le code {0}.' -f $LASTEXITCODE) }
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'Ces lanceurs sont destines a Windows.' }
    switch ($Action) {
        'Stop' { Invoke-Stop }
        'StopLegacy' { Invoke-LegacyCleanup }
        'Diagnostic' { Invoke-Diagnostic }
    }
    exit 0
} catch {
    Write-ControlError $_.Exception.Message
    exit 1
}
