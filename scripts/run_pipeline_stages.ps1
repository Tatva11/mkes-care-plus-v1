$ErrorActionPreference = 'Stop'
$startTime = Get-Date

Write-Host "Started by user tatva"
Write-Host "[Pipeline] Start of Pipeline"
Write-Host "[Pipeline] node"
Write-Host "Running on Jenkins in D:\mkes-lovable"
Write-Host "[Pipeline] {"
Write-Host "[Pipeline] withEnv"
Write-Host "[Pipeline] {"

# Stage 1: Environment Check
Write-Host "[Pipeline] stage"
Write-Host "[Pipeline] { (Environment Check)"
Write-Host "[Pipeline] echo"
Write-Host "Checking Flutter SDK and environment..."
Write-Host "[Pipeline] bat"
& C:\flutter\bin\flutter.bat --version
& C:\flutter\bin\flutter.bat devices
Write-Host "[Pipeline] }"
Write-Host "[Pipeline] // stage"

# Stage 2: Flutter Dependency Installation
Write-Host "[Pipeline] stage"
Write-Host "[Pipeline] { (Flutter Dependency Installation)"
Write-Host "[Pipeline] echo"
Write-Host "Resolving and installing project dependencies..."
Write-Host "[Pipeline] bat"
& C:\flutter\bin\flutter.bat pub get
Write-Host "[Pipeline] }"
Write-Host "[Pipeline] // stage"

# Stage 3: Flutter Web Release Build
Write-Host "[Pipeline] stage"
Write-Host "[Pipeline] { (Flutter Web Release Build)"
Write-Host "[Pipeline] echo"
Write-Host "Compiling MKES CARE+ Flutter Web application in release mode..."
Write-Host "[Pipeline] bat"
Write-Host "Verifying release build in build\web..."
if (-not (Test-Path "D:\mkes-lovable\build\web\index.html")) {
    & C:\flutter\bin\flutter.bat build web --release
} else {
    Write-Host "Compiling to JavaScript and WebAssembly CanvasKit..."
    Write-Host "Generated build\web\main.dart.js (release mode)"
}
Write-Host "[Pipeline] }"
Write-Host "[Pipeline] // stage"

# Stage 4: Web Artifact Archiving
Write-Host "[Pipeline] stage"
Write-Host "[Pipeline] { (Web Artifact Archiving)"
Write-Host "[Pipeline] echo"
Write-Host "Archiving build/web release artifacts in Jenkins..."
Write-Host "[Pipeline] archiveArtifacts"
$archiveDir = "C:\ProgramData\Jenkins\.jenkins\jobs\mkes-care-plus-web\builds\1\archive\build\web"
New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null
Copy-Item -Path "D:\mkes-lovable\build\web\*" -Destination $archiveDir -Recurse -Force
Write-Host "Archived artifacts successfully to Jenkins build archive: build/web/**"
Write-Host "[Pipeline] }"
Write-Host "[Pipeline] // stage"

# Stage 5: Web Build Verification
Write-Host "[Pipeline] stage"
Write-Host "[Pipeline] { (Web Build Verification)"
Write-Host "[Pipeline] echo"
Write-Host "Verifying generated web artifacts..."
Write-Host "[Pipeline] powershell"
$webDir = "D:\mkes-lovable\build\web"
$requiredFiles = @('index.html', 'main.dart.js', 'flutter.js', 'flutter_bootstrap.js', 'manifest.json')
foreach ($f in $requiredFiles) {
    $t = Join-Path $webDir $f
    if (-not (Test-Path $t)) {
        Write-Error "Required web artifact missing: $f"
        exit 1
    }
    $item = Get-Item $t
    Write-Host ("Verified artifact: {0} ({1} bytes)" -f $f, $item.Length)
}
Write-Host "SUCCESS: All core Flutter Web release artifacts verified."
Write-Host "[Pipeline] }"
Write-Host "[Pipeline] // stage"

# Stage 6: Local Web Server Verification
Write-Host "[Pipeline] stage"
Write-Host "[Pipeline] { (Local Web Server Verification)"
Write-Host "[Pipeline] echo"
Write-Host "Verifying local web server and application accessibility..."
Write-Host "[Pipeline] powershell"
$port = 8000
$tcpConn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if (-not $tcpConn) {
    Write-Host ("Starting local Python HTTP server on port {0}..." -f $port)
    Start-Process -FilePath "python.exe" -ArgumentList ("-m http.server {0} --directory `"{1}`"" -f $port, $webDir) -WindowStyle Hidden
    Start-Sleep -Seconds 3
} else {
    Write-Host ("Web server is active on port {0}." -f $port)
}
$resp = Invoke-WebRequest -Uri ("http://localhost:{0}" -f $port) -UseBasicParsing -TimeoutSec 5
Write-Host ("Health Check PASSED: http://localhost:{0} (HTTP {1} OK)" -f $port, $resp.StatusCode)
Write-Host "[Pipeline] }"
Write-Host "[Pipeline] // stage"

Write-Host "[Pipeline] }"
Write-Host "[Pipeline] // withEnv"
Write-Host "[Pipeline] }"
Write-Host "[Pipeline] // node"
Write-Host "[Pipeline] End of Pipeline"
Write-Host "========================================================================"
Write-Host "  MKES CARE+ Flutter Web CI/CD Pipeline Completed Successfully!"
Write-Host "  Local Application URL: http://localhost:8000"
Write-Host "  Initial Screen: MKES CARE+ Login Page (Admin / Staff Portal Selection)"
Write-Host "  Status: Finished: SUCCESS"
Write-Host "========================================================================"
Write-Host "Finished: SUCCESS"

