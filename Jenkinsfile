pipeline {
    agent any

    environment {
        FLUTTER_HOME = 'C:\\flutter'
        PATH = "C:\\flutter\\bin;C:\\Windows\\System32;C:\\Windows;C:\\Windows\\System32\\WindowsPowerShell\\v1.0;C:\\Program Files\\Git\\cmd;${env.PATH}"
    }

    stages {
        stage('Environment Check') {
            steps {
                echo 'Checking Flutter SDK and environment...'
                bat 'call flutter --version'
                bat 'call flutter devices'
            }
        }

        stage('Flutter Dependency Installation') {
            steps {
                echo 'Resolving and installing project dependencies...'
                bat '''
                    @echo off
                    if not exist api.env (
                        echo Creating placeholder api.env for build
                        echo SUPABASE_URL=https://placeholder.supabase.co > api.env
                        echo SUPABASE_ANON_KEY=placeholder-anon-key >> api.env
                    )
                    call flutter pub get
                '''
            }
        }

        stage('Flutter Web Release Build') {
            steps {
                echo 'Compiling MKES CARE+ Flutter Web application in release mode...'
                bat 'call flutter build web --release'
            }
        }

        stage('Web Artifact Archiving') {
            steps {
                echo 'Archiving build/web release artifacts in Jenkins...'
                archiveArtifacts artifacts: 'build/web/**', fingerprint: true, allowEmptyArchive: false
            }
        }

        stage('Web Build Verification') {
            steps {
                echo 'Verifying generated web artifacts...'
                powershell '''
                    $webDir = Join-Path $PWD 'build\\web'
                    $requiredFiles = @('index.html', 'main.dart.js', 'flutter.js', 'flutter_bootstrap.js', 'manifest.json')
                    
                    foreach ($file in $requiredFiles) {
                        $target = Join-Path $webDir $file
                        if (-not (Test-Path $target)) {
                            Write-Error "Required web artifact missing: $file"
                            exit 1
                        }
                        $item = Get-Item $target
                        Write-Host "Verified artifact: $file ($($item.Length) bytes)"
                    }
                    Write-Host "SUCCESS: All core Flutter Web release artifacts verified."
                '''
            }
        }

        stage('Local Web Server Verification') {
            steps {
                echo 'Verifying local web server and application accessibility...'
                powershell '''
                    $port = 8000
                    $webDir = Join-Path $PWD 'build\\web'

                    $tcpConn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
                    if (-not $tcpConn) {
                        Write-Host "Starting local Python HTTP server on port $port..."
                        Start-Process -FilePath "python.exe" -ArgumentList "-m http.server $port --directory `"$webDir`"" -WindowStyle Hidden
                        Start-Sleep -Seconds 3
                    } else {
                        Write-Host "Web server is active on port $port."
                    }

                    try {
                        $resp = Invoke-WebRequest -Uri "http://localhost:$port" -UseBasicParsing -TimeoutSec 5
                        if ($resp.StatusCode -eq 200) {
                            Write-Host "Health Check PASSED: http://localhost:$port (HTTP 200 OK)"
                        } else {
                            Write-Error "Unexpected status code: $($resp.StatusCode)"
                            exit 1
                        }
                    } catch {
                        Write-Error "Health check failed for http://localhost:$port : $_"
                        exit 1
                    }
                '''
            }
        }
    }

    post {
        success {
            echo '========================================================================'
            echo '  MKES CARE+ Flutter Web CI/CD Pipeline Completed Successfully!'
            echo '  Local Application URL: http://localhost:8000'
            echo '  Initial Screen: MKES CARE+ Login Page (Admin / Staff Portal Selection)'
            echo '  Status: Finished: SUCCESS'
            echo '========================================================================'
        }
        failure {
            echo 'Pipeline failed. Check Jenkins console output for details.'
        }
    }
}
