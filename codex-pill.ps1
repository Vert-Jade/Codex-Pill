#requires -Version 5.1
<#
Codex Pill 2.2 - widget de bureau Windows.
Codex : journaux locaux en lecture seule. Claude : service d'usage du compte
(comme /usage), avec la connexion locale de Claude Code, jamais copiée.
Aucune installation de paquet ni droit administrateur.
#>
[CmdletBinding()]
param(
    [switch]$Diagnostic,
    [switch]$Demo,
    [string]$CodexHomePath
)

$ErrorActionPreference = 'Stop'
$script:PillVersion = '2.2.0'
$script:PillScriptPath = $PSCommandPath
$script:PillDirectory = $PSScriptRoot
$script:PillDemoMode = [bool]$Demo
$script:PillExiting = $false
$script:PillUi = $null
$script:PillSnapshot = $null
$script:PillWorker = $null
$script:PillWorkerResult = $null
$script:PillRunspace = $null
$script:PillShared = $null
$script:PillTimer = $null
$script:PillStopSignal = $null
$script:PillShowSignal = $null
$script:PillMutex = $null
$script:PillOwnsMutex = $false
$script:PillExitCode = 0
$script:PillStateDirectory = $null
$script:PillLastError = ''
$script:PillTray = $null

function Write-PillLog {
    param($ErrorDetail)
    try {
        if (-not $script:PillStateDirectory) { return }
        $errorText = [string]$ErrorDetail
        if ($ErrorDetail -is [Management.Automation.ErrorRecord]) {
            $errorText = $ErrorDetail.Exception.ToString() + "`r`n" + $ErrorDetail.ScriptStackTrace
        }
        $logPath = Join-Path $script:PillStateDirectory 'error.log'
        if ([IO.File]::Exists($logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 1048576) {
            Move-Item -LiteralPath $logPath -Destination ($logPath + '.previous') -Force
        }
        [IO.File]::AppendAllText($logPath, ('[{0}] {1}{2}' -f [DateTimeOffset]::Now.ToString('o'), $errorText, "`r`n"), [Text.UTF8Encoding]::new($true))
    } catch { }
}

function Read-PillSettings {
    $settingsObject = @{ Left = $null; Top = $null; Topmost = $true; HideConsole = $true; Provider = 'Codex'; Opacity = 0.94; CodexHomePath = ''; ClaudeHomePath = '' }
    if (Test-Path -LiteralPath $script:PillSettingsPath) {
        try {
            $savedObject = Get-Content -LiteralPath $script:PillSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($coordinateName in @('Left','Top')) {
                if ($null -ne $savedObject.$coordinateName) {
                    $coordinateValue = [double]$savedObject.$coordinateName
                    if (-not [double]::IsNaN($coordinateValue) -and -not [double]::IsInfinity($coordinateValue)) { $settingsObject[$coordinateName] = $coordinateValue }
                }
            }
            if ($savedObject.Topmost -is [bool]) { $settingsObject.Topmost = $savedObject.Topmost }
            if ($savedObject.HideConsole -is [bool]) { $settingsObject.HideConsole = $savedObject.HideConsole }
            if ($null -ne $savedObject.Opacity) { $settingsObject.Opacity = [Math]::Max(0.65, [Math]::Min(1, [double]$savedObject.Opacity)) }
            if ($savedObject.CodexHomePath -is [string]) { $settingsObject.CodexHomePath = $savedObject.CodexHomePath }
            if ($savedObject.ClaudeHomePath -is [string]) { $settingsObject.ClaudeHomePath = $savedObject.ClaudeHomePath }
            if ($savedObject.Provider -in @('Codex','Claude')) { $settingsObject.Provider = [string]$savedObject.Provider }
        } catch { Write-PillLog $_ }
    }
    return $settingsObject
}

function Write-PillJsonAtomic {
    param([string]$Path, $Value)
    $temporaryPath = $Path + '.' + $PID + '.tmp'
    try {
        [IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($true))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporaryPath, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporaryPath, $Path) }
    } finally {
        if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
    }
}

function Save-PillSettings {
    try {
        if ($null -ne $script:PillUi) {
            $script:PillSettings.Left = $script:PillUi.Main.Left
            $script:PillSettings.Top = $script:PillUi.Main.Top
            $script:PillSettings.Topmost = $script:PillUi.Main.Topmost
        }
        Write-PillJsonAtomic $script:PillSettingsPath $script:PillSettings
    } catch { Write-PillLog $_ }
}

function Initialize-PillConsole {
    if ('CodexPill.NativeConsole' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
namespace CodexPill {
    public static class NativeConsole {
        [DllImport("kernel32.dll")]
        private static extern IntPtr GetConsoleWindow();
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FreeConsole();
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AllocConsole();
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetConsoleTitle(string title);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ShowWindow(IntPtr handle, int command);

        public static void Hide() {
            if (GetConsoleWindow() == IntPtr.Zero) return;
            // Detach this widget only. Never search for or hide a Terminal
            // window that could contain other tabs or PowerShell processes.
            if (!FreeConsole()) throw new Win32Exception(Marshal.GetLastWin32Error());
            Console.SetOut(TextWriter.Null);
            Console.SetError(TextWriter.Null);
            Console.SetIn(TextReader.Null);
        }

        public static void Show() {
            IntPtr handle = GetConsoleWindow();
            if (handle == IntPtr.Zero) {
                if (!AllocConsole()) throw new Win32Exception(Marshal.GetLastWin32Error());
                handle = GetConsoleWindow();
            }
            // .NET streams may still refer to a previously detached console.
            Console.SetOut(new StreamWriter(Console.OpenStandardOutput()) { AutoFlush = true });
            Console.SetError(new StreamWriter(Console.OpenStandardError()) { AutoFlush = true });
            Console.SetIn(new StreamReader(Console.OpenStandardInput()));
            SetConsoleTitle("Codex Pill - Fenetre de commande");
            // SW_SHOWNOACTIVATE. The return value is the PREVIOUS visibility,
            // not a success flag. A newly allocated console is already shown.
            if (handle != IntPtr.Zero) ShowWindow(handle, 4);
        }
    }
}
'@
}

function Set-PillConsoleHidden {
    param([bool]$Hidden)
    # The standalone diagnostic must always retain its output window.
    if ($Diagnostic) { return }
    Initialize-PillConsole
    if ($Hidden) {
        [CodexPill.NativeConsole]::Hide()
    } else {
        [CodexPill.NativeConsole]::Show()
        [Console]::WriteLine(('Codex Pill ' + $script:PillVersion))
        [Console]::WriteLine('Le widget reste actif. Pour masquer cette fenetre :')
        [Console]::WriteLine('clic droit sur la pastille > Masquer la fenetre de commande.')
        [Console]::WriteLine('Pour quitter : clic droit sur la pastille > Quitter Codex Pill.')
        [Console]::WriteLine(('Journal : ' + (Join-Path $script:PillStateDirectory 'error.log')))
    }
    # Update the preference only after the native operation succeeded.
    $script:PillSettings.HideConsole = $Hidden
}

function Resolve-PillCodexHome {
    param([string]$Override)
    $candidatePath = $Override
    if ([string]::IsNullOrWhiteSpace($candidatePath)) { $candidatePath = $script:PillSettings.CodexHomePath }
    if ([string]::IsNullOrWhiteSpace($candidatePath)) { $candidatePath = $env:CODEX_HOME }
    if ([string]::IsNullOrWhiteSpace($candidatePath)) { $candidatePath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex' }
    $candidatePath = [Environment]::ExpandEnvironmentVariables($candidatePath)
    return [IO.Path]::GetFullPath($candidatePath)
}

function Resolve-PillClaudeHome {
    $candidatePath = $script:PillSettings.ClaudeHomePath
    if ([string]::IsNullOrWhiteSpace($candidatePath)) { $candidatePath = $env:CLAUDE_CONFIG_DIR }
    if ([string]::IsNullOrWhiteSpace($candidatePath)) { $candidatePath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude' }
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($candidatePath))
}

function Refresh-PillClaudeIntegration {
    try { $script:PillClaudeIntegration = Get-ClaudePillIntegrationState -ClaudeHome $script:PillClaudeHome }
    catch { Write-PillLog $_; $script:PillClaudeIntegration = [pscustomobject]@{ Status = 'Error'; Message = $_.Exception.Message } }
}

function New-PillWaitingSnapshot {
    [pscustomobject]@{
        Provider = $script:PillSettings.Provider; Now = [DateTimeOffset]::UtcNow
        LastUpdated = $null; Status = 'Waiting'; Primary = $null; Secondary = $null
        Activity = @(); LastProject = ''; LastSession = ''
    }
}

function Set-PillProvider {
    param([ValidateSet('Codex','Claude')][string]$Provider)
    if ($script:PillSettings.Provider -eq $Provider) { return }
    $script:PillSettings.Provider = $Provider
    Save-PillSettings
    if ($Provider -eq 'Claude') { Refresh-PillClaudeIntegration }
    if ($null -ne $script:PillShared) {
        $script:PillShared.Snapshot = $null
        $script:PillShared.Provider = $Provider
        Request-PillRefresh
    }
    $script:PillSnapshot = $null
    $script:PillUi.ActivitySignature = ''
    Update-PillProviderControls
    if ($script:PillDemoMode) { Update-PillUi (New-PillDemoSnapshot) }
    else { Update-PillUi (New-PillWaitingSnapshot) }
    Update-PillTray
}

function Enable-PillClaudeTracking {
    try {
        $result = Enable-ClaudePillIntegration -ClaudeHome $script:PillClaudeHome
        if ($result.Status -eq 'ExistingStatusLine') {
            $question = "Claude Code possède déjà une ligne de statut personnalisée. La sauvegarder et la remplacer par le suivi Codex Pill ? Vous pourrez la restaurer avec « Désactiver le suivi Claude Code »."
            $answer = [Windows.MessageBox]::Show($question, 'Suivi Claude Code', [Windows.MessageBoxButton]::YesNo, [Windows.MessageBoxImage]::Question)
            if ($answer -ne [Windows.MessageBoxResult]::Yes) { return }
            $result = Enable-ClaudePillIntegration -ClaudeHome $script:PillClaudeHome -ReplaceExisting
        }
        if ($result.Status -ne 'Enabled') { throw ('Activation impossible : ' + $result.Status) }
        Refresh-PillClaudeIntegration
        Update-PillProviderControls
        Request-PillRefresh
        Update-PillUi (New-PillWaitingSnapshot)
        [void][Windows.MessageBox]::Show("La barre de statut est activée dans Claude Code en terminal. Les quotas du compte restent lus directement, y compris depuis l’extension VS Code.", 'Suivi Claude Code')
    } catch { Write-PillLog $_; [void][Windows.MessageBox]::Show($_.Exception.Message, 'Suivi Claude Code') }
}

function Disable-PillClaudeTracking {
    try {
        $result = Disable-ClaudePillIntegration -ClaudeHome $script:PillClaudeHome
        if ($result.Status -eq 'ChangedExternally') {
            [void][Windows.MessageBox]::Show('La ligne de statut a été modifiée depuis son activation. Elle a été conservée telle quelle.', 'Suivi Claude Code')
        }
        Refresh-PillClaudeIntegration
        Update-PillProviderControls
        Request-PillRefresh
    } catch { Write-PillLog $_; [void][Windows.MessageBox]::Show($_.Exception.Message, 'Suivi Claude Code') }
}

function Set-PillStartup {
    param([bool]$Enabled)
    if (-not $Enabled) { Remove-Item -LiteralPath $script:PillStartupLink -Force -ErrorAction SilentlyContinue; return }
    $shellObject = $null; $shortcutObject = $null
    try {
        $shellObject = New-Object -ComObject WScript.Shell
        $shortcutObject = $shellObject.CreateShortcut($script:PillStartupLink)
        $shortcutObject.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $shortcutObject.Arguments = '-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $script:PillDirectory 'CodexPill.Launch.ps1') + '"'
        $shortcutObject.WorkingDirectory = $script:PillDirectory
        $shortcutObject.WindowStyle = 7
        $shortcutObject.Description = 'Codex Pill - utilisation des quotas Codex'
        $shortcutIconPath = Join-Path $script:PillDirectory 'assets\CodexPill.ico'
        if (Test-Path -LiteralPath $shortcutIconPath) { $shortcutObject.IconLocation = $shortcutIconPath + ',0' }
        $shortcutObject.Save()
    } finally {
        if ($null -ne $shortcutObject) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcutObject) }
        if ($null -ne $shellObject) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shellObject) }
    }
}

function Request-PillRefresh {
    if ($null -ne $script:PillShared) { $script:PillShared.ForceRefresh = $true; [void]$script:PillShared.Wake.Set() }
}

function Select-PillSource {
    $pickerObject = [Windows.Forms.FolderBrowserDialog]::new()
    $isClaude = $script:PillSettings.Provider -eq 'Claude'
    try {
        $pickerObject.Description = if ($isClaude) { 'Choisis le dossier de configuration .claude de Claude Code.' } else { 'Choisis le dossier .codex contenant le sous-dossier sessions.' }
        $pickerObject.ShowNewFolderButton = $false
        $currentSource = if ($isClaude) { $script:PillClaudeHome } else { $script:PillCodexHome }
        if (Test-Path -LiteralPath $currentSource -PathType Container) { $pickerObject.SelectedPath = $currentSource }
        if ($pickerObject.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
            $selectedFolder = $pickerObject.SelectedPath
            if (-not $isClaude -and -not (Test-Path -LiteralPath (Join-Path $selectedFolder 'sessions') -PathType Container)) {
                [void][Windows.MessageBox]::Show('Ce dossier ne contient pas de sous-dossier sessions. Sélectionne le dossier .codex utilisé par Codex.', 'Codex Pill')
                return
            }
            if ($isClaude) {
                $script:PillSettings.ClaudeHomePath = $selectedFolder
                $script:PillClaudeHome = $selectedFolder
                if ($null -ne $script:PillShared) { $script:PillShared.ClaudeHome = $selectedFolder }
                Refresh-PillClaudeIntegration
            } else {
                $script:PillSettings.CodexHomePath = $selectedFolder
                $script:PillCodexHome = $selectedFolder
                if ($null -ne $script:PillShared) { $script:PillShared.CodexHome = $selectedFolder }
            }
            Save-PillSettings
            if ($null -ne $script:PillShared) { $script:PillShared.Snapshot = $null }
            Update-PillProviderControls
            Update-PillUi (New-PillWaitingSnapshot)
            Request-PillRefresh
        }
    } catch { Write-PillLog $_ } finally { $pickerObject.Dispose() }
}

function Open-PillErrorLog {
    $logPath = Join-Path $script:PillStateDirectory 'error.log'
    if (-not (Test-Path -LiteralPath $logPath)) { [IO.File]::WriteAllText($logPath, "Aucune erreur enregistrée.`r`n", [Text.UTF8Encoding]::new($true)) }
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\notepad.exe') -ArgumentList ('"' + $logPath + '"')
}

function New-PillDemoSnapshot {
    $demoNow = [DateTimeOffset]::UtcNow
    return [pscustomobject]@{
        Provider = $script:PillSettings.Provider; Now = $demoNow; LastUpdated = $demoNow; Status = 'Ready'; LastProject = 'Projet web'; LastSession = 'demo-1'; Plan = ''
        Primary = [pscustomobject]@{ UsedPercent = 28; RemainingPercent = 72; ResetAt = $demoNow.AddMinutes(134); WindowMinutes = 300; IsExpired = $false; IsStale = $false; ObservedAt = $demoNow }
        Secondary = [pscustomobject]@{ UsedPercent = 54; RemainingPercent = 46; ResetAt = $demoNow.AddDays(3).AddHours(8); WindowMinutes = 10080; IsExpired = $false; IsStale = $false; ObservedAt = $demoNow }
        Activity = @(
            [pscustomobject]@{ Project = 'Projet web'; SessionId = 'demo-1'; LastActivity = $demoNow.AddMinutes(-2); TotalTokens = 124800 },
            [pscustomobject]@{ Project = 'Application'; SessionId = 'demo-2'; LastActivity = $demoNow.AddMinutes(-24); TotalTokens = 67200 },
            [pscustomobject]@{ Project = 'Codex Pill'; SessionId = 'demo-3'; LastActivity = $demoNow.AddMinutes(-48); TotalTokens = 31800 }
        )
    }
}

function Start-PillReader {
    $initialProvider = 'Codex'
    if ($null -ne $script:PillSettings -and $script:PillSettings.Provider -eq 'Claude') { $initialProvider = 'Claude' }
    $script:PillShared = [hashtable]::Synchronized(@{
        Exiting = $false; Snapshot = $null; ErrorText = ''; ForceRefresh = $true
        Provider = $initialProvider; CodexHome = $script:PillCodexHome; ClaudeHome = $script:PillClaudeHome
        Wake = [Threading.AutoResetEvent]::new($false)
    })
    $workerCode = {
        param($PackageDirectory, $SharedState)
        $ErrorActionPreference = 'Stop'
        $readerState = $null; $activeProvider = ''; $activeHome = ''
        try {
            . (Join-Path $PackageDirectory 'CodexPill.Core.ps1')
            . (Join-Path $PackageDirectory 'ClaudePill.Core.ps1')
            while (-not $SharedState.Exiting) {
                try {
                    $requestedProvider = [string]$SharedState.Provider
                    $requestedHome = if ($requestedProvider -eq 'Claude') { $SharedState.ClaudeHome } else { $SharedState.CodexHome }
                    if ($activeHome -ne $requestedHome -or $activeProvider -ne $requestedProvider -or $null -eq $readerState) {
                        if ($null -ne $readerState) {
                            if ($activeProvider -eq 'Claude') { Close-ClaudePillReader -Reader $readerState }
                            else { Close-CodexPillReader -Reader $readerState }
                        }
                        $activeHome = $requestedHome; $activeProvider = $requestedProvider
                        $readerState = if ($activeProvider -eq 'Claude') { New-ClaudePillReader -ClaudeHome $activeHome } else { New-CodexPillReader -CodexHome $activeHome }
                    }
                    $forceScanNow = [bool]$SharedState.ForceRefresh
                    $SharedState.ForceRefresh = $false
                    if ($activeProvider -eq 'Claude') {
                        Update-ClaudePillReader -Reader $readerState -ForceScan:$forceScanNow | Out-Null
                        $newSnapshot = Get-ClaudePillSnapshot -Reader $readerState
                    } else {
                        Update-CodexPillReader -Reader $readerState -ForceScan:$forceScanNow | Out-Null
                        $newSnapshot = Get-CodexPillSnapshot -Reader $readerState
                    }
                    $newSnapshot | Add-Member -NotePropertyName Provider -NotePropertyValue $activeProvider -Force
                    $newSnapshot | Add-Member -NotePropertyName SourceHome -NotePropertyValue $activeHome -Force
                    # Discard a result if the user changed provider/source while it was read.
                    $currentHome = if ($activeProvider -eq 'Claude') { $SharedState.ClaudeHome } else { $SharedState.CodexHome }
                    if ($activeProvider -eq $SharedState.Provider -and $activeHome -eq $currentHome) { $SharedState.Snapshot = $newSnapshot }
                    $SharedState.ErrorText = ''
                } catch { $SharedState.ErrorText = $_.Exception.Message }
                if (-not $SharedState.Exiting) {
                    $delayMilliseconds = 4000
                    if ($null -ne $SharedState.Snapshot -and ($SharedState.Snapshot.Diagnostics.IsScanning -or $SharedState.Snapshot.Diagnostics.IsCatchingUp)) { $delayMilliseconds = 250 }
                    [void]$SharedState.Wake.WaitOne($delayMilliseconds)
                }
            }
        } catch { $SharedState.ErrorText = $_.Exception.Message }
        finally {
            if ($null -ne $readerState) {
                if ($activeProvider -eq 'Claude') { Close-ClaudePillReader -Reader $readerState }
                else { Close-CodexPillReader -Reader $readerState }
            }
        }
    }
    $script:PillRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $script:PillRunspace.ApartmentState = 'MTA'
    $script:PillRunspace.ThreadOptions = 'ReuseThread'
    $script:PillRunspace.Open()
    $script:PillWorker = [PowerShell]::Create()
    $script:PillWorker.Runspace = $script:PillRunspace
    [void]$script:PillWorker.AddScript($workerCode.ToString()).AddArgument($script:PillDirectory).AddArgument($script:PillShared)
    $script:PillWorkerResult = $script:PillWorker.BeginInvoke()
}

function Stop-PillReader {
    if ($null -eq $script:PillShared) { return }
    $script:PillShared.Exiting = $true
    [void]$script:PillShared.Wake.Set()
    $workerFinished = $true
    if ($null -ne $script:PillWorkerResult) {
        $workerFinished = $script:PillWorkerResult.AsyncWaitHandle.WaitOne(1800)
        if (-not $workerFinished) {
            $stopResult = $script:PillWorker.BeginStop($null, $null)
            $workerFinished = $stopResult.AsyncWaitHandle.WaitOne(1000)
            if ($workerFinished) { try { $script:PillWorker.EndStop($stopResult) } catch { } }
        }
        if ($workerFinished) { try { [void]$script:PillWorker.EndInvoke($script:PillWorkerResult) } catch { } }
    }
    if ($workerFinished) {
        if ($null -ne $script:PillWorker) { $script:PillWorker.Dispose() }
        if ($null -ne $script:PillRunspace) { $script:PillRunspace.Dispose() }
        $script:PillShared.Wake.Dispose()
    }
    # A stalled read never keeps the UI waiting indefinitely. The host exits
    # after cleanup; the external controller can additionally verify its exit.
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Codex Pill est une application Windows (WPF). Les tests du lecteur sont multiplateformes.' }
    $script:PillStateDirectory = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'CodexPill'
    [void][IO.Directory]::CreateDirectory($script:PillStateDirectory)
    $script:PillSettingsPath = Join-Path $script:PillStateDirectory 'settings.json'
    $script:PillInstancePath = Join-Path $script:PillStateDirectory 'instance.json'
    $script:PillStartupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Pill.lnk'
    $script:PillSettings = Read-PillSettings
    $script:PillCodexHome = Resolve-PillCodexHome $CodexHomePath
    $script:PillClaudeHome = Resolve-PillClaudeHome
    foreach ($requiredFile in @('CodexPill.Core.ps1','CodexPill.Ui.ps1','CodexPill.Launch.ps1','CodexPill.Tray.ps1','ClaudePill.Core.ps1','ClaudePill.Integration.ps1','ClaudePill.StatusLine.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $script:PillDirectory $requiredFile) -PathType Leaf)) { throw ('Fichier manquant : ' + $requiredFile + ". Extrais toute l’archive dans le même dossier.") }
    }
    . (Join-Path $script:PillDirectory 'ClaudePill.Core.ps1')
    . (Join-Path $script:PillDirectory 'ClaudePill.Integration.ps1')
    Refresh-PillClaudeIntegration
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Le mode STA est nécessaire. Utilise Lancer Codex Pill.vbs ou Lancer Codex Pill.cmd.' }

    if ($Diagnostic) {
        Write-Output ('Codex Pill ' + $script:PillVersion)
        Write-Output ('PowerShell : ' + $PSVersionTable.PSVersion + ' / ' + [IntPtr]::Size * 8 + ' bits')
        Write-Output ('Fournisseur : ' + $script:PillSettings.Provider)
        Write-Output ('Dossier Codex : ' + $script:PillCodexHome)
        Write-Output ('Dossier Claude : ' + $script:PillClaudeHome)
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
        . (Join-Path $script:PillDirectory 'CodexPill.Ui.ps1')
        $diagnosticUi = New-PillUi
        $script:PillUi = $diagnosticUi
        $script:PillDemoMode = $true
        Update-PillProviderControls
        Update-PillUi (New-PillDemoSnapshot)
        $diagnosticUi.Main.Measure([Windows.Size]::new(1000, 800))
        $diagnosticUi.Detail.Measure([Windows.Size]::new(408, 800))
        $diagnosticUi.Detail.Close(); $diagnosticUi.Main.Close()
        $script:PillUi = $null
        Write-Output 'Interface WPF : construction, donnees et mesures OK.'
        if ($script:PillSettings.Provider -eq 'Claude') {
            $diagnosticReader = New-ClaudePillReader -ClaudeHome $script:PillClaudeHome
            Update-ClaudePillReader -Reader $diagnosticReader -ForceScan | Out-Null
            $diagnosticSnapshot = Get-ClaudePillSnapshot -Reader $diagnosticReader
            Close-ClaudePillReader -Reader $diagnosticReader
            Write-Output ('Barre de statut Claude Code : ' + $script:PillClaudeIntegration.Status)
            Write-Output ('Source des quotas Claude : ' + $diagnosticSnapshot.Source + ' ' + $diagnosticSnapshot.ApiError + ' ' + $diagnosticSnapshot.Plan)
        } else {
            . (Join-Path $script:PillDirectory 'CodexPill.Core.ps1')
            $diagnosticReader = New-CodexPillReader -CodexHome $script:PillCodexHome
            Update-CodexPillReader -Reader $diagnosticReader -ForceScan | Out-Null
            $diagnosticSnapshot = Get-CodexPillSnapshot -Reader $diagnosticReader
            Close-CodexPillReader -Reader $diagnosticReader
        }
        Write-Output ('Lecture des journaux : ' + $diagnosticSnapshot.Status)
        Write-Output ('Derniere mesure : ' + $diagnosticSnapshot.LastUpdated)
        Write-Output ('Sessions affichees : ' + @($diagnosticSnapshot.Activity).Count)
        Write-Output 'Diagnostic termine. Aucun nouveau widget en arriere-plan.'
    } else {
        $identityObject = [Security.Principal.WindowsIdentity]::GetCurrent()
        try { $userSid = $identityObject.User.Value } finally { $identityObject.Dispose() }
        $script:PillMutex = [Threading.Mutex]::new($false, ('Local\CodexPill.Instance.' + $userSid))
        try { $script:PillOwnsMutex = $script:PillMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $script:PillOwnsMutex = $true }
        if (-not $script:PillOwnsMutex) {
            try { $existingSignal = [Threading.EventWaitHandle]::OpenExisting(('Local\CodexPill.Show.' + $userSid)); [void]$existingSignal.Set(); $existingSignal.Dispose() } catch { }
            return
        }
        $script:PillStopSignal = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::AutoReset, ('Local\CodexPill.Stop.' + $userSid))
        $script:PillShowSignal = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::AutoReset, ('Local\CodexPill.Show.' + $userSid))
        try { Set-PillConsoleHidden -Hidden ([bool]$script:PillSettings.HideConsole) }
        catch { Write-PillLog $_; $script:PillSettings.HideConsole = $false }
        # Migrate only this widget's already-enabled startup shortcut.
        if (Test-Path -LiteralPath $script:PillStartupLink) {
            try { Set-PillStartup -Enabled $true } catch { Write-PillLog $_ }
        }
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
        . (Join-Path $script:PillDirectory 'CodexPill.Ui.ps1')
        . (Join-Path $script:PillDirectory 'CodexPill.Tray.ps1')
        $script:PillUi = New-PillUi
        Connect-PillUi
        $applicationObject = [Windows.Application]::new()
        $applicationObject.ShutdownMode = 'OnMainWindowClose'
        $applicationObject.MainWindow = $script:PillUi.Main
        $applicationObject.Add_DispatcherUnhandledException({
            param($senderObject, $dispatcherEvent)
            Write-PillLog $dispatcherEvent.Exception
            $dispatcherEvent.Handled = $true
            $script:PillUi.Controls.StatusText.Text = 'Erreur enregistrée · ouvrir le journal depuis le menu.'
        })
        $currentProcess = [Diagnostics.Process]::GetCurrentProcess()
        try {
            $instanceRecord = @{ ProcessId = $PID; StartTimeUtc = $currentProcess.StartTime.ToUniversalTime().ToString('o'); ScriptPath = [IO.Path]::GetFullPath($script:PillScriptPath); Version = $script:PillVersion }
            Write-PillJsonAtomic $script:PillInstancePath $instanceRecord
        } finally { $currentProcess.Dispose() }
        Update-PillProviderControls
        if ($Demo) { Update-PillUi (New-PillDemoSnapshot) } else { Update-PillUi (New-PillWaitingSnapshot); Start-PillReader }
        $script:PillTimer = [Windows.Threading.DispatcherTimer]::new()
        $script:PillTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $script:PillTickNumber = 0
        $script:PillTimer.Add_Tick({
            try {
                if ($script:PillStopSignal.WaitOne(0)) { $script:PillUi.Main.Close(); return }
                if ($script:PillShowSignal.WaitOne(0)) { Show-PillWidget -ResetPosition; Save-PillSettings }
                $script:PillTickNumber++
                if (($script:PillTickNumber % 2) -ne 0 -or $script:PillDemoMode) { return }
                if ($null -ne $script:PillShared.Snapshot) { Update-PillUi $script:PillShared.Snapshot }
                if ($script:PillShared.ErrorText) {
                    if ($script:PillLastError -ne $script:PillShared.ErrorText) { Write-PillLog $script:PillShared.ErrorText; $script:PillLastError = $script:PillShared.ErrorText }
                    $workerHasStopped = $null -ne $script:PillWorkerResult -and $script:PillWorkerResult.IsCompleted
                    $script:PillUi.Controls.StatusText.Text = if ($workerHasStopped) { 'Lecteur arrêté · consulter le journal et relancer le widget.' } else { 'Lecture interrompue · nouvelle tentative automatique' }
                    $script:PillUi.Controls.StatusDot.Fill = Get-PillBrush $script:PillUi.Theme.Warning
                }
            } catch { Write-PillLog $_ }
        })
        $script:PillTimer.Start()
        [void]$applicationObject.Run($script:PillUi.Main)
    }
} catch {
    $script:PillExitCode = 1
    Write-PillLog $_
    $startupError = $_.Exception.Message
    if ($Diagnostic) { Write-Output ('ERREUR : ' + $startupError) }
    else {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $errorNotice = "Codex Pill n’a pas pu démarrer.`r`n`r`n" + $startupError
            if ($script:PillStateDirectory) { $errorNotice += "`r`n`r`nDétails : " + (Join-Path $script:PillStateDirectory 'error.log') }
            $errorNotice += "`r`nLance Diagnostic Codex Pill.cmd pour vérifier le dossier."
            [void][Windows.Forms.MessageBox]::Show($errorNotice, 'Codex Pill', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error)
        } catch { Write-Output ('Codex Pill : ' + $startupError) }
    }
} finally {
    $script:PillExiting = $true
    if ($null -ne $script:PillTimer) { $script:PillTimer.Stop() }
    if (Get-Command Remove-PillTray -ErrorAction SilentlyContinue) { try { Remove-PillTray } catch { Write-PillLog $_ } }
    try { Stop-PillReader } catch { Write-PillLog $_ }
    if ($script:PillOwnsMutex -and $script:PillInstancePath) {
        try {
            if (Test-Path -LiteralPath $script:PillInstancePath) {
                $remainingRecord = Get-Content -LiteralPath $script:PillInstancePath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([int]$remainingRecord.ProcessId -eq $PID) { Remove-Item -LiteralPath $script:PillInstancePath -Force }
            }
        } catch { Write-PillLog $_ }
    }
    if ($null -ne $script:PillStopSignal) { $script:PillStopSignal.Dispose() }
    if ($null -ne $script:PillShowSignal) { $script:PillShowSignal.Dispose() }
    if ($null -ne $script:PillMutex) {
        if ($script:PillOwnsMutex) { try { $script:PillMutex.ReleaseMutex() } catch { } }
        $script:PillMutex.Dispose()
    }
}
exit $script:PillExitCode
