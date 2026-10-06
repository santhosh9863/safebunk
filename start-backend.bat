@echo off
REM PULSE backend launcher — keep this running during college hours for
REM notifications (absent roasts, class reminders, Sunday chill) to arrive.
REM Optionally start minimized:  start-backend.bat minimized
cd /d "%~dp0safebunk-backend"
if not exist dist\main.js (
  echo Building backend...
  call npm run build
)
if /i "%~1"=="minimized" (
  start "" /min cmd /c "node dist/main"
  exit /b
)
node dist/main