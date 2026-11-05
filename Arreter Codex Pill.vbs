Option Explicit

Dim sh, fs, folder, controlPath, powershellPath, command, result, runError, runDescription
On Error Resume Next
Set sh = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
If Err.Number <> 0 Then
    MsgBox "Impossible de preparer l'arret. Utilisez Arreter Codex Pill.cmd.", 16, "Codex Pill"
    WScript.Quit 1
End If
On Error GoTo 0

folder = fs.GetParentFolderName(WScript.ScriptFullName)
controlPath = fs.BuildPath(folder, "CodexPill.Control.ps1")
powershellPath = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
If Not fs.FileExists(controlPath) Then
    MsgBox "CodexPill.Control.ps1 est introuvable. Extrayez TOUT le ZIP avant de continuer.", 16, "Codex Pill"
    WScript.Quit 1
End If
If Not fs.FileExists(powershellPath) Then
    MsgBox "Windows PowerShell est introuvable sur cet ordinateur.", 16, "Codex Pill"
    WScript.Quit 1
End If

command = Quote(powershellPath) & " -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Quote(controlPath) & " -Action Stop -Silent"
On Error Resume Next
sh.CurrentDirectory = folder
result = sh.Run(command, 0, True)
runError = Err.Number
runDescription = Err.Description
On Error GoTo 0
If runError <> 0 Then
    MsgBox "Impossible d'envoyer la demande d'arret : " & runDescription, 16, "Codex Pill"
    WScript.Quit 1
End If
If result <> 0 Then
    MsgBox "L'arret de Codex Pill n'a pas pu etre confirme. Lancez Diagnostic Codex Pill.cmd pour afficher les details.", 48, "Codex Pill"
    WScript.Quit result
End If

Function Quote(value)
    Quote = Chr(34) & value & Chr(34)
End Function
