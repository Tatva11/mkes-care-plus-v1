@echo off
REM ============================================================================
REM MKES CARE+ — Windows Service Setup Script (PM2)
REM Run this script as Administrator on the clinic reception Windows PC.
REM ============================================================================

echo ============================================================================
echo   MKES CARE+ WhatsApp Bridge — Windows Background Service Installer
echo ============================================================================

REM Check for Administrative privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] This installer must be executed as Administrator!
    echo Please right-click install_windows_service.bat and select 'Run as Administrator'.
    pause
    exit /b 1
)

echo.
echo [1/5] Checking Node.js installation...
node -v >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Node.js is not installed or not in PATH! Please install Node.js v18 or v20 LTS.
    pause
    exit /b 1
)
node -v

echo.
echo [2/5] Creating persistent session directory C:\MKES_CARE_PLUS\wa_session...
if not exist "C:\MKES_CARE_PLUS\wa_session" (
    mkdir "C:\MKES_CARE_PLUS\wa_session"
    echo Created directory C:\MKES_CARE_PLUS\wa_session
) else (
    echo Directory C:\MKES_CARE_PLUS\wa_session already exists.
)

echo.
echo [3/6] Ensuring environment configuration (.env) and secret protection...
cd /d "%~dp0\.."
if not exist ".env" (
    echo [NOTICE] No .env file found. Creating safe default .env from .env.example...
    copy ".env.example" ".env" >nul
    echo Created .env with DRY_RUN=true (safe simulation mode).
    echo [ACTION REQUIRED] Please edit .env to insert your production Supabase Service Role Key when ready.
) else (
    echo Existing .env detected. Preserving production configuration.
)

echo.
echo [4/6] Installing microservice dependencies...
call npm install --omit=dev

echo.
echo [5/6] Installing PM2 and PM2 Windows Service globally...
call npm install -g pm2 pm2-windows-service

echo.
echo [6/6] Registering Windows Service 'MKES_WhatsApp_Daemon'...
set PM2_SERVICE_SCRIPTS="%~dp0..\index.js"
REM Stop and remove any pre-existing instance to prevent duplicate process conflicts
call pm2 delete mkes-wa-bridge >nul 2>&1

if not exist "C:\MKES_CARE_PLUS\wa_session\Default" (
    echo [NOTICE] WhatsApp pairing has not yet been completed.
    echo If this is initial installation, run 'npm start' interactively to scan the QR code first.
)

call pm2 start index.js --name "mkes-wa-bridge" --max-memory-restart 1200M --restart-delay 3000 --exp-backoff-restart-delay 100
call pm2 save
call pm2-service-install -n MKES_WhatsApp_Daemon

echo.
echo ============================================================================
echo   Installation Complete!
echo   Service 'MKES_WhatsApp_Daemon' is installed and configured for auto-start.
echo   - Default Safety Mode: DRY_RUN=true (real WhatsApp messages blocked)
echo   - Session Storage: C:\MKES_CARE_PLUS\wa_session (persistent)
echo   - To view live logs: pm2 logs mkes-wa-bridge
echo   - To monitor status: pm2 status
echo   - To verify running process: tasklist ^| findstr /i node.exe
echo ============================================================================
pause


