' ============================================================================
'  SNOW launcher (this is what the desktop shortcut runs).
'
'  Quietly updates from GitHub, then starts the game directly: no console
'  window, no Godot editor, no Play button. If something needs your attention
'  (no Git, no Godot, an update that could not be applied) one message box says
'  so; the game still starts whenever it can.
'
'  The updater is copied to the temp folder and run from there, so an update
'  that replaces the launcher files can never disturb a launch in progress.
' ============================================================================
Option Explicit
Dim shell, fso, launcherDir, projectDir, q, tempUpdater, rc

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
launcherDir = fso.GetParentFolderName(WScript.ScriptFullName)
projectDir = fso.GetParentFolderName(launcherDir)
q = Chr(34)

Function ReadText(path)
    ReadText = ""
    If fso.FileExists(path) Then
        Dim f
        Set f = fso.OpenTextFile(path, 1)
        If Not f.AtEndOfStream Then ReadText = f.ReadAll
        f.Close
    End If
End Function

' 1. Update (hidden, wait for it).
tempUpdater = shell.ExpandEnvironmentStrings("%TEMP%") & "\snow_update_run.bat"
On Error Resume Next
If fso.FileExists(tempUpdater) Then fso.DeleteFile tempUpdater, True
fso.CopyFile launcherDir & "\snow_update.bat", tempUpdater, True
If Err.Number <> 0 Or Not fso.FileExists(tempUpdater) Then
    ' Could not use the temp folder: run the updater where it is.
    tempUpdater = launcherDir & "\snow_update.bat"
End If
Err.Clear
On Error GoTo 0
rc = shell.Run("cmd.exe /c " & q & q & tempUpdater & q & " " & q & projectDir & q & q, 0, True)
Dim why
why = ReadText(launcherDir & "\update_notice.txt")
If why <> "" Then
    MsgBox why & vbCrLf & vbCrLf & "SNOW will now start with the version already installed.", vbExclamation, "SNOW"
End If

' 2. Start the game (hidden console, the game window appears normally).
rc = shell.Run("cmd.exe /c " & q & q & launcherDir & "\snow_run.bat" & q & " " & q & projectDir & q & q, 0, True)
Dim problem
problem = ReadText(launcherDir & "\run_notice.txt")
If problem <> "" Then
    MsgBox problem, vbCritical, "SNOW"
End If
