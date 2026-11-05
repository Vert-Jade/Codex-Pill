# Claude Code statusLine integration. Dot-source ClaudePill.Core.ps1 first.
# No automatic setup: the app calls Enable only after the user selects it.

function Write-CLPJsonAtomic {
    param([string]$Path, $Value)
    $temporaryPath = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporaryPath, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporaryPath, $Path) }
    } finally { if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) } }
}

function Enable-ClaudePillIntegration {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ClaudeHome, [switch]$ReplaceExisting)
    $ClaudeHome = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ClaudeHome))
    $state = Get-ClaudePillIntegrationState -ClaudeHome $ClaudeHome
    if ($state.Status -eq 'Error') { throw $state.Message }
    if ($state.Status -eq 'ExistingStatusLine' -and -not $ReplaceExisting) {
        return [pscustomobject]@{ Status = 'ExistingStatusLine'; Message = 'Une barre de statut existe deja. Une confirmation est necessaire pour la sauvegarder et la remplacer.'; SettingsPath = $state.SettingsPath }
    }
    $integrationDirectory = Join-Path $ClaudeHome 'codex-pill'
    $receiverSource = Join-Path $PSScriptRoot 'ClaudePill.StatusLine.ps1'
    if (-not [IO.File]::Exists($receiverSource)) { throw 'Le collecteur ClaudePill.StatusLine.ps1 est manquant.' }
    [void][IO.Directory]::CreateDirectory($integrationDirectory)
    $receiverTarget = Join-Path $integrationDirectory 'ClaudePill.StatusLine.ps1'
    # EncodedCommand avoids shell-dependent quoting rules for spaces, apostrophes
    # and dollar signs in Windows paths (Git Bash or PowerShell may invoke it).
    $invokeReceiver = "& '" + $receiverTarget.Replace("'", "''") + "'"
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($invokeReceiver))
    $ownedCommand = 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $encodedCommand
    $manifestPath = Join-Path $integrationDirectory 'integration.json'
    if ($state.Status -eq 'Enabled') {
        [IO.File]::Copy($receiverSource, $receiverTarget, $true)
        return [pscustomobject]@{ Status = 'Enabled'; Message = 'Suivi Claude Code deja active ; collecteur actualise.'; SettingsPath = $state.SettingsPath }
    }
    $settingsPath = $state.SettingsPath
    $settings = [pscustomobject]@{}
    if ([IO.File]::Exists($settingsPath)) { $settings = [IO.File]::ReadAllText($settingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop }
    if ($settings -isnot [pscustomobject]) { throw 'Le fichier settings.json Claude doit contenir un objet JSON.' }
    $existingProperty = $settings.PSObject.Properties['statusLine']
    $previousStatusLine = $null
    $hadStatusLine = $null -ne $existingProperty
    if ($hadStatusLine) { $previousStatusLine = $existingProperty.Value }
    $backupPath = $null
    if ([IO.File]::Exists($settingsPath)) {
        $backupPath = Join-Path $integrationDirectory ('settings-before-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
        [IO.File]::Copy($settingsPath, $backupPath, $false)
    }
    $manifest = [ordered]@{ Version = 1; OwnedCommand = $ownedCommand; HadStatusLine = $hadStatusLine; PreviousStatusLine = $previousStatusLine; BackupPath = $backupPath; InstalledAt = [DateTimeOffset]::UtcNow.ToString('o') }
    [IO.File]::Copy($receiverSource, $receiverTarget, $true)
    Write-CLPJsonAtomic $manifestPath $manifest
    $settings | Add-Member -MemberType NoteProperty -Name statusLine -Value ([pscustomobject]@{ type = 'command'; command = $ownedCommand }) -Force
    Write-CLPJsonAtomic $settingsPath $settings
    return [pscustomobject]@{ Status = 'Enabled'; Message = 'Suivi active. Ouvre Claude Code et attends une reponse pour recevoir ses quotas.'; SettingsPath = $settingsPath; BackupPath = $backupPath }
}

function Disable-ClaudePillIntegration {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ClaudeHome)
    $ClaudeHome = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ClaudeHome))
    $settingsPath = Join-Path $ClaudeHome 'settings.json'
    $manifestPath = Join-Path (Join-Path $ClaudeHome 'codex-pill') 'integration.json'
    if (-not [IO.File]::Exists($manifestPath) -or -not [IO.File]::Exists($settingsPath)) {
        return [pscustomobject]@{ Status = 'Disabled'; Message = 'Le suivi Claude Code est deja desactive.'; SettingsPath = $settingsPath }
    }
    $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    $settings = [IO.File]::ReadAllText($settingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    $currentCommand = [string](Get-CLPProperty (Get-CLPProperty $settings 'statusLine') 'command')
    if ($currentCommand -cne [string](Get-CLPProperty $manifest 'OwnedCommand')) {
        return [pscustomobject]@{ Status = 'ChangedExternally'; Message = 'La barre de statut a ete modifiee depuis. Aucun changement effectue.'; SettingsPath = $settingsPath }
    }
    if ([bool](Get-CLPProperty $manifest 'HadStatusLine')) {
        $settings | Add-Member -MemberType NoteProperty -Name statusLine -Value (Get-CLPProperty $manifest 'PreviousStatusLine') -Force
    } else { $settings.PSObject.Properties.Remove('statusLine') }
    Write-CLPJsonAtomic $settingsPath $settings
    return [pscustomobject]@{ Status = 'Disabled'; Message = 'Suivi desactive. La barre de statut precedente a ete restauree.'; SettingsPath = $settingsPath }
}
