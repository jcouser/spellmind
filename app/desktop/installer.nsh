; Spellmind's additions to electron-builder's NSIS installer (docs/milestone-21.md). Modeled on
; NeverQuestAlone's app/desktop/build/installer.nsh (MIT; see NOTICE.md).

; A running Spellmind, closed for an install or an update. electron-builder's own check asked the
; player to click OK, then killed it (the player, 2026-11-13: "Spellmind also needed to be closed"):
; the app treats a window's close as "to the tray", so a plain taskkill only hid it. Here the
; installer asks it to quit itself (a second launch with --quit: it says goodbye to the game and
; ends), waits, then ends whatever is left (the app, its worker, the screen-reading helper).
!macro customCheckAppRunning
  ${If} ${FileExists} "$INSTDIR\${APP_EXECUTABLE_FILENAME}"
    nsExec::Exec `"$INSTDIR\${APP_EXECUTABLE_FILENAME}" --quit`
    Pop $0
    Sleep 3000
  ${EndIf}
  nsExec::Exec `"$SYSDIR\cmd.exe" /C taskkill /F /T /IM "${APP_EXECUTABLE_FILENAME}" /FI "USERNAME eq %USERNAME%"`
  Pop $0
  nsExec::Exec `"$SYSDIR\cmd.exe" /C taskkill /F /IM "spellmind-capture.exe" /FI "USERNAME eq %USERNAME%"`
  Pop $0
  Sleep 500
!macroend

; Uninstall (not an update's): the start-at-login entry main.mjs writes (the HKCU Run value named
; after the app id) and Explorer's on/off flag for it. The settings and the saved keys stay, as the
; settings folder does (a reinstall finds them).
!macro customUnInstall
  ${IfNot} ${isUpdated}
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "gg.spellmind.app"
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" "gg.spellmind.app"
  ${EndIf}
!macroend
