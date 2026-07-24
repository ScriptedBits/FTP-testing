# FTP Load Test Script
# Tests login → change directory → upload → logoff repeatedly
# Testing for intermittent printer scan-to-FTP issues
# MIT License - Copyright (c) 2026 ScriptedBits


#------------------------------------------------------------------------------------------------
# For automated testing create a ftpconfig.ini file in the same directory as the ftptest.ps1 file.
# If you run the script with no ftpconfig.ini found the script can create one for you.
# Setup up the ftpconfig.ini file with these settings
# Supports logging when Log=True in ftpconfig.ini

# [FTP]
# Server=192.168.1.50
# Path=/scans
# Username=scanner
# Password=YourPassword
# Loops=20
# Delay=3
# Mode=Passive
# Retries=1
# IntegrityCheck=False
# Log=True
#------------------------------------------------------------------------------------------------

param()

$ScriptVersion = "1.10"
$ErrorActionPreference = "Stop"

Write-Host "FTP Load Test Script  v$ScriptVersion" -ForegroundColor Cyan
Write-Host ""

# -------------------------------------------------
# Load or ask for configuration
# -------------------------------------------------
$configFile = Join-Path $PSScriptRoot "ftpconfig.ini"

function Read-Ini {
    param([string]$Path)
    $ini = @{}
    $section = ""
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -match "^\[(.+)\]$") {
            $section = $matches[1]
            $ini[$section] = @{}
        }
        elseif ($line -match "^(.+?)\s*=\s*(.*)$" -and $section) {
            $ini[$section][$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    return $ini
}

function Save-Ini {
    param(
        [string]$Path,
        [string]$Server,
        [string]$RemotePath,
        [string]$Username,
        [string]$Password,
        [int]$Loops,
        [int]$Delay,
        [string]$Mode,
        [int]$Retries,
        [bool]$IntegrityCheck,
        [bool]$LogEnabled
    )

    $content = @"
; FTP Testing Script v$ScriptVersion
; Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

[FTP]
Server=$Server
Path=$RemotePath
Username=$Username
Password=$Password
Loops=$Loops
Delay=$Delay
Mode=$Mode
Retries=$Retries
IntegrityCheck=$($IntegrityCheck.ToString())
Log=$($LogEnabled.ToString())
"@

    $content | Out-File -FilePath $Path -Encoding UTF8
    Write-Host "Settings saved to: $Path" -ForegroundColor Green
}

$server          = $null
$path            = $null
$user            = $null
$pass            = $null
$loops           = $null
$delay           = 2
$logEnabled      = $false
$mode            = "Passive"
$retries         = 1
$integrityCheck  = $true

if (Test-Path $configFile) {
    Write-Host "Found ftpconfig.ini - loading settings..." -ForegroundColor Cyan
    $ini = Read-Ini -Path $configFile

    $server     = $ini["FTP"]["Server"]
    $path       = $ini["FTP"]["Path"]
    $user       = $ini["FTP"]["Username"]
    $pass       = $ini["FTP"]["Password"]
    $loops      = [int]$ini["FTP"]["Loops"]
    if ($ini["FTP"]["Delay"])          { $delay          = [int]$ini["FTP"]["Delay"] }
    if ($ini["FTP"]["Log"])            { $logEnabled     = ($ini["FTP"]["Log"] -eq "True") }
    if ($ini["FTP"]["Mode"])           { $mode           = $ini["FTP"]["Mode"] }
    if ($ini["FTP"]["Retries"])        { $retries        = [int]$ini["FTP"]["Retries"] }
    if ($ini["FTP"]["IntegrityCheck"]) { $integrityCheck = ($ini["FTP"]["IntegrityCheck"] -eq "True") }
}
else {
    Write-Host "No ftpconfig.ini found - please enter the details:" -ForegroundColor Yellow
    $server = Read-Host "FTP Server IP / Hostname"
    $path   = Read-Host "Remote path (e.g. /upload or /)"
    $user   = Read-Host "Username"
    $secure = Read-Host "Password" -AsSecureString
    $BSTR   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $pass   = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    $loops  = [int](Read-Host "Number of times to test the transfer")
    $delay  = [int](Read-Host "Delay between tests in seconds (recommended 2-5)")
    $mode   = Read-Host "Mode (Passive/Active) [Passive]"
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "Passive" }
    $retries = [int](Read-Host "Automatic retries on failure [1]")
    if (-not $retries) { $retries = 1 }
    $intAns = Read-Host "Perform integrity check (download + hash)? (Y/N) [Y]"
    $integrityCheck = -not ($intAns -match "^[Nn]")
    $logAns = Read-Host "Enable logging to text file? (Y/N)"
    $logEnabled = ($logAns -match "^[Yy]")

    Write-Host ""
    $saveAns = Read-Host "Do you want to save these settings to ftpconfig.ini for next time? (Y/N)"
    if ($saveAns -match "^[Yy]") {
        $pathForIni = if ([string]::IsNullOrWhiteSpace($path)) { "/" } else { $path }
        Save-Ini -Path $configFile -Server $server -RemotePath $pathForIni -Username $user -Password $pass `
                 -Loops $loops -Delay $delay -Mode $mode -Retries $retries -IntegrityCheck $integrityCheck -LogEnabled $logEnabled
    }
}

# Normalize path
if (-not $path.StartsWith("/")) { $path = "/" + $path }
if ($path -eq "/") { $path = "" }

$usePassive = ($mode -eq "Passive")

Write-Host ""
Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  Server          : $server"
Write-Host "  Path            : $($path -replace '^$','/')"
Write-Host "  Username        : $user"
Write-Host "  Loops           : $loops"
Write-Host "  Delay           : $delay second(s)"
Write-Host "  Mode            : $mode"
Write-Host "  Retries         : $retries"
Write-Host "  Integrity Check : $integrityCheck"
Write-Host "  Logging         : $logEnabled"
Write-Host ""

# -------------------------------------------------
# Helper Functions
# -------------------------------------------------
function New-FtpRequest {
    param([string]$Uri, [string]$Method, [string]$Username, [string]$Password, [bool]$UsePassive)
    $req = [System.Net.FtpWebRequest]::Create($Uri)
    $req.Credentials = New-Object System.Net.NetworkCredential($Username, $Password)
    $req.Method = $Method
    $req.UseBinary = $true
    $req.UsePassive = $UsePassive
    $req.KeepAlive = $false
    $req.Timeout = 15000
    return $req
}

function Invoke-FtpCommand {
    param(
        $Server, $RemotePath, $Method,
        $LocalFile = $null, $DownloadTo = $null,
        $Username, $Password, $UsePassive
    )

    $uri = if ($LocalFile -or $DownloadTo) {
        $fileName = if ($LocalFile) { Split-Path $LocalFile -Leaf } else { Split-Path $DownloadTo -Leaf }
        "ftp://$Server$RemotePath/$fileName"
    } else {
        "ftp://$Server$RemotePath"
    }

    try {
        $req = New-FtpRequest -Uri $uri -Method $Method -Username $Username -Password $Password -UsePassive $UsePassive

        if ($LocalFile -and $Method -eq [System.Net.WebRequestMethods+Ftp]::UploadFile) {
            $fileContent = [System.IO.File]::ReadAllBytes($LocalFile)
            $req.ContentLength = $fileContent.Length
            $stream = $req.GetRequestStream()
            $stream.Write($fileContent, 0, $fileContent.Length)
            $stream.Close()
        }

        $resp = $req.GetResponse()

        if ($DownloadTo -and $Method -eq [System.Net.WebRequestMethods+Ftp]::DownloadFile) {
            $responseStream = $resp.GetResponseStream()
            $fileStream = [System.IO.File]::Create($DownloadTo)
            $responseStream.CopyTo($fileStream)
            $fileStream.Close()
            $responseStream.Close()
        }

        $status = "$($resp.StatusCode) - $($resp.StatusDescription)".Trim()
        $resp.Close()
        return @{ Success = $true; Message = $status }
    }
    catch [System.Net.WebException] {
        $msg = $_.Exception.Message

        if ($_.Exception.Response -ne $null) {
            try {
                $ftpResp = [System.Net.FtpWebResponse]$_.Exception.Response
                $code = $ftpResp.StatusCode
                $desc = if ($ftpResp.StatusDescription) { $ftpResp.StatusDescription.Trim() } else { "" }
                $msg = "$code - $desc".Trim(" -")
                $ftpResp.Close()
            }
            catch { }
        }

        return @{ Success = $false; Message = $msg }
    }
    catch {
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

# -------------------------------------------------
# DNS Reliability Check
# -------------------------------------------------
Write-Host "Running DNS Reliability Check (10 lookups)..." -ForegroundColor Cyan

$dnsSuccess = 0
$dnsFail    = 0
$dnsResults = @()

for ($d = 1; $d -le 10; $d++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $result = [System.Net.Dns]::GetHostAddresses($server)
        $sw.Stop()
        $ipList = ($result | ForEach-Object { $_.IPAddressToString }) -join ", "
        $ms = $sw.ElapsedMilliseconds
        Write-Host "  Lookup $d : OK ($ms`ms) → $ipList" -ForegroundColor Green
        $dnsSuccess++
        $dnsResults += "Lookup $d : OK ($ms`ms) → $ipList"
    }
    catch {
        $sw.Stop()
        $ms = $sw.ElapsedMilliseconds
        Write-Host "  Lookup $d : FAILED ($ms`ms) → $($_.Exception.Message)" -ForegroundColor Red
        $dnsFail++
        $dnsResults += "Lookup $d : FAILED ($ms`ms) → $($_.Exception.Message)"
    }
    Start-Sleep -Milliseconds 200
}

Write-Host ""
Write-Host "DNS Results: $dnsSuccess successful / $dnsFail failed" -ForegroundColor $(if ($dnsFail -gt 1) {"Yellow"} else {"Green"})

if ($dnsFail -gt 1) {
    Write-Host ""
    Write-Host "WARNING: DNS resolution is unreliable!" -ForegroundColor Red
    Write-Host "This is very likely the cause of intermittent scan failures." -ForegroundColor Red
    Write-Host "Strongly recommended: Use the IP address instead of the hostname/FQDN." -ForegroundColor Yellow
    Write-Host ""
}

# -------------------------------------------------
# Initial FTP Connection Test
# -------------------------------------------------
Write-Host "Testing initial FTP connection..." -ForegroundColor Cyan

$initialTest = Invoke-FtpCommand -Server $server -RemotePath $path `
                                 -Method ([System.Net.WebRequestMethods+Ftp]::ListDirectory) `
                                 -Username $user -Password $pass -UsePassive $usePassive

if (-not $initialTest.Success) {
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Red
    Write-Host "  ERROR: Cannot connect to the FTP server!" -ForegroundColor Red
    Write-Host "=======================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Server   : $server" -ForegroundColor Yellow
    Write-Host "Path     : $($path -replace '^$','/')" -ForegroundColor Yellow

    # Force a clear message
    $errorDetails = $initialTest.Message
    if ([string]::IsNullOrWhiteSpace($errorDetails) -or $errorDetails -eq "Undefined") {
        $errorDetails = "Unable to connect to the FTP server (connection failed)"
    }

    Write-Host "Details  : $errorDetails" -ForegroundColor Red
    Write-Host ""

    if ($dnsFail -eq 10) {
        Write-Host "IMPORTANT: All 10 DNS lookups failed!" -ForegroundColor Red
        Write-Host "The hostname '$server' cannot be resolved." -ForegroundColor Red
        Write-Host "Please change the Server value in ftpconfig.ini to the IP address instead of the hostname." -ForegroundColor Yellow
    }
    else {
        Write-Host "Possible causes:" -ForegroundColor Yellow
        Write-Host "  - Wrong IP address / hostname"
        Write-Host "  - Wrong username or password"
        Write-Host "  - Wrong path"
        Write-Host "  - FTP service not running"
        Write-Host "  - Firewall blocking the connection"
        Write-Host "  - Passive mode / port issues"
    }

    Write-Host ""
    Write-Host "Script stopped. No further tests will be run." -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host "Initial FTP connection successful!" -ForegroundColor Green
Write-Host ""

# -------------------------------------------------
# Logging setup
# -------------------------------------------------
$logFile = $null
$logLines = @()

if ($logEnabled) {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $logFile = Join-Path $PSScriptRoot "FTPTest_Log_$timestamp.txt"
    
    $logLines += "FTP Load Test Log"
    $logLines += "================="
    $logLines += "Script Version  : $ScriptVersion"
    $logLines += "Started         : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $logLines += "Server          : $server"
    $logLines += "Path            : $($path -replace '^$','/')"
    $logLines += "Username        : $user"
    $logLines += "Loops           : $loops"
    $logLines += "Delay           : $delay second(s)"
    $logLines += "Mode            : $mode"
    $logLines += "Retries         : $retries"
    $logLines += "Integrity Check : $integrityCheck"
    $logLines += ""
    $logLines += "----- DNS Reliability Check -----"
    $logLines += "Successful : $dnsSuccess"
    $logLines += "Failed     : $dnsFail"
    $dnsResults | ForEach-Object { $logLines += "  $_" }
    $logLines += ""
    $logLines += "----- Initial Connection Test -----"
    $logLines += "Result: SUCCESS"
    $logLines += ""
    $logLines += "----- Test Results -----"
    $logLines += ""
}

# -------------------------------------------------
# Create dummy test files
# -------------------------------------------------
$tempDir = Join-Path $env:TEMP "FTPTest_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir | Out-Null

$sizes = @(
    @{ Name = "1KB";  Size = 1KB },
    @{ Name = "10KB"; Size = 10KB },
    @{ Name = "100KB";Size = 100KB },
    @{ Name = "1MB";  Size = 1MB }
)

$testFiles = @()
foreach ($s in $sizes) {
    $file = Join-Path $tempDir "test_$($s.Name).bin"
    $bytes = New-Object byte[] $s.Size
    (New-Object System.Random).NextBytes($bytes)
    [System.IO.File]::WriteAllBytes($file, $bytes)
    $testFiles += $file
    Write-Host "Created dummy file: $($s.Name)"
}
Write-Host ""

# -------------------------------------------------
# Main test loop
# -------------------------------------------------
$success = 0
$failed  = 0
$startTime = Get-Date
$errors = @()

Write-Host "Starting $loops transfer test(s) | Mode: $mode | Retries: $retries | Integrity: $integrityCheck | Delay: $delay`s" -ForegroundColor Cyan
Write-Host ("=" * 80)

for ($i = 1; $i -le $loops; $i++) {

    $fileToUpload = $testFiles[($i - 1) % $testFiles.Count]
    $sizeName     = (Split-Path $fileToUpload -Leaf) -replace "test_|\.bin",""
    $originalHash = (Get-FileHash -Path $fileToUpload -Algorithm SHA256).Hash

    $percent = [math]::Round(($i / $loops) * 100)
    Write-Progress -Activity "FTP Load Test v$ScriptVersion" `
                   -Status "Test $i of $loops | $sizeName | OK: $success Fail: $failed" `
                   -PercentComplete $percent

    $attempt = 0
    $testSuccess = $false
    $finalMessage = ""
    $loginMs = 0
    $uploadMs = 0
    $integrity = "Skipped"

    while ($attempt -le $retries -and -not $testSuccess) {
        $attempt++
        $attemptInfo = if ($attempt -gt 1) { " (Retry $($attempt-1))" } else { "" }

        Write-Host "[$i/$loops] $sizeName$attemptInfo ... " -NoNewline

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $loginResult = Invoke-FtpCommand -Server $server -RemotePath $path `
                                         -Method ([System.Net.WebRequestMethods+Ftp]::ListDirectory) `
                                         -Username $user -Password $pass -UsePassive $usePassive
        $sw.Stop()
        $loginMs = $sw.ElapsedMilliseconds

        if (-not $loginResult.Success) {
            $finalMessage = "LOGIN/CWD FAILED ($loginMs`ms) → $($loginResult.Message)"
            Write-Host $finalMessage -ForegroundColor Red
            continue
        }

        $sw.Restart()
        $uploadResult = Invoke-FtpCommand -Server $server -RemotePath $path `
                                          -Method ([System.Net.WebRequestMethods+Ftp]::UploadFile) `
                                          -LocalFile $fileToUpload `
                                          -Username $user -Password $pass -UsePassive $usePassive
        $sw.Stop()
        $uploadMs = $sw.ElapsedMilliseconds

        if (-not $uploadResult.Success) {
            $finalMessage = "UPLOAD FAILED (Login ${loginMs}ms / Upload ${uploadMs}ms) → $($uploadResult.Message)"
            Write-Host $finalMessage -ForegroundColor Red
            continue
        }

        if ($integrityCheck) {
            $downloadFile = Join-Path $tempDir "download_check.bin"
            $dlResult = Invoke-FtpCommand -Server $server -RemotePath $path `
                                          -Method ([System.Net.WebRequestMethods+Ftp]::DownloadFile) `
                                          -DownloadTo $downloadFile `
                                          -Username $user -Password $pass -UsePassive $usePassive

            if ($dlResult.Success) {
                $downloadedHash = (Get-FileHash -Path $downloadFile -Algorithm SHA256).Hash
                Remove-Item $downloadFile -Force -ErrorAction SilentlyContinue

                if ($downloadedHash -eq $originalHash) {
                    $integrity = "PASS"
                    $testSuccess = $true
                    $finalMessage = "OK | Login ${loginMs}ms | Upload ${uploadMs}ms | Integrity: PASS"
                    Write-Host $finalMessage -ForegroundColor Green
                }
                else {
                    $integrity = "FAIL (hash mismatch)"
                    $finalMessage = "INTEGRITY FAILED → Hash mismatch"
                    Write-Host $finalMessage -ForegroundColor Red
                }
            }
            else {
                $integrity = "FAIL (download error)"
                $finalMessage = "INTEGRITY FAILED → $($dlResult.Message)"
                Write-Host $finalMessage -ForegroundColor Red
            }
        }
        else {
            $integrity = "Skipped"
            $testSuccess = $true
            $finalMessage = "OK | Login ${loginMs}ms | Upload ${uploadMs}ms | Integrity: Skipped"
            Write-Host $finalMessage -ForegroundColor Green
        }
    }

    if ($testSuccess) { $success++ }
    else {
        $failed++
        $errors += "[$i] $finalMessage"
    }

    if ($logEnabled) {
        $logLines += "[$i/$loops] $sizeName | Attempts: $attempt | Login: ${loginMs}ms | Upload: ${uploadMs}ms | Integrity: $integrity | $finalMessage"
    }

    if ($i -lt $loops -and $delay -gt 0) {
        Start-Sleep -Seconds $delay
    }
}

Write-Progress -Activity "FTP Load Test v$ScriptVersion" -Completed
$duration = (Get-Date) - $startTime

# -------------------------------------------------
# Cleanup & Summary
# -------------------------------------------------
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ("=" * 80)
Write-Host "Finished in $([math]::Round($duration.TotalSeconds,1)) seconds"
Write-Host "Successful : $success" -ForegroundColor Green
Write-Host "Failed     : $failed"  -ForegroundColor $(if ($failed -gt 0) {"Red"} else {"Green"})

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Error details:" -ForegroundColor Yellow
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}

if ($logEnabled) {
    $logLines += ""
    $logLines += "----- Summary -----"
    $logLines += "Finished   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $logLines += "Duration   : $([math]::Round($duration.TotalSeconds,1)) seconds"
    $logLines += "Successful : $success"
    $logLines += "Failed     : $failed"
    $logLines += ""
    if ($errors.Count -gt 0) {
        $logLines += "Error details:"
        $errors | ForEach-Object { $logLines += "  $_" }
    }
    $logLines | Out-File -FilePath $logFile -Encoding UTF8
    Write-Host ""
    Write-Host "Log written to: $logFile" -ForegroundColor Cyan
}

Write-Host ""