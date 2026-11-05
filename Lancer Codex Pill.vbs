Option Explicit

Dim sh, fs, folder, scriptPath, powershellPath, command, runError, runDescription
On Error Resume Next
Set sh = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
If Err.Number <> 0 Then
    MsgBox "Impossible de preparer Codex Pill. Utilisez Lancer Codex Pill.cmd.", 16, "Codex Pill"
    WScript.Quit 1
End If
On Error GoTo 0

folder = fs.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fs.BuildPath(folder, "CodexPill.Launch.ps1")
powershellPath = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
If Not fs.FileExists(scriptPath) Then
    MsgBox "CodexPill.Launch.ps1 est introuvable. Extrayez TOUT le ZIP dans un dossier avant de lancer Codex Pill.", 16, "Codex Pill"
    WScript.Quit 1
End If
If Not fs.FileExists(powershellPath) Then
    MsgBox "Windows PowerShell est introuvable sur cet ordinateur.", 16, "Codex Pill"
    WScript.Quit 1
End If

command = Quote(powershellPath) & " -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Quote(scriptPath)
On Error Resume Next
sh.CurrentDirectory = folder
sh.Run command, 0, False
runError = Err.Number
runDescription = Err.Description
On Error GoTo 0
If runError <> 0 Then
    MsgBox "Le lancement a echoue : " & runDescription & vbCrLf & "Utilisez Diagnostic Codex Pill.cmd pour afficher les details.", 16, "Codex Pill"
    WScript.Quit 1
End If

Function Quote(value)
    Quote = Chr(34) & value & Chr(34)
End Function
