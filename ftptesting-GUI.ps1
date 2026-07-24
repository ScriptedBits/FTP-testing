# FTP Load Test Script - GUI Version
# Tests login / change directory / upload / logoff repeatedly
# Testing for intermittent printer scan-to-FTP issues
# MIT License - Copyright (c) 2026 ScriptedBits

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptVersion = "2.1"
$ErrorActionPreference = "Stop"
$script:StopRequested = $false

# ---------- Colors ----------
$bgColor       = [System.Drawing.Color]::FromArgb(32, 32, 32)
$inputBg       = [System.Drawing.Color]::FromArgb(45, 45, 45)
$textColor     = [System.Drawing.Color]::FromArgb(220, 220, 220)
$accentGreen   = [System.Drawing.Color]::FromArgb(0, 150, 80)
$accentRed     = [System.Drawing.Color]::FromArgb(180, 50, 50)
$accentBlue    = [System.Drawing.Color]::FromArgb(0, 120, 215)

# -------------------------------------------------
# Helper Functions
# -------------------------------------------------
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
    param($Path, $Server, $RemotePath, $Username, $Password, $Loops, $Delay, $Mode, $Retries, $IntegrityCheck, $LogEnabled)

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
}

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
    param($Server, $RemotePath, $Method, $LocalFile = $null, $DownloadTo = $null, $Username, $Password, $UsePassive)

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
            } catch {}
        }
        return @{ Success = $false; Message = $msg }
    }
    catch {
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

function Write-Log {
    param([string]$Text, [string]$Color = "LightGray")
    $txtResults.SelectionStart = $txtResults.TextLength
    $txtResults.SelectionLength = 0

    switch ($Color) {
        "Red"        { $txtResults.SelectionColor = [System.Drawing.Color]::Salmon }
        "DarkGreen"  { $txtResults.SelectionColor = [System.Drawing.Color]::LightGreen }
        "DarkBlue"   { $txtResults.SelectionColor = [System.Drawing.Color]::SkyBlue }
        "DarkOrange" { $txtResults.SelectionColor = [System.Drawing.Color]::Orange }
        default      { $txtResults.SelectionColor = [System.Drawing.Color]::LightGray }
    }

    $txtResults.AppendText("$Text`r`n")
    $txtResults.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# -------------------------------------------------
# Build the GUI (Dark Theme)
# -------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "FTP Load Test  v$ScriptVersion"
$form.Size = New-Object System.Drawing.Size(780, 720)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = $bgColor
$form.ForeColor = $textColor

# --- Server ---
$lblServer = New-Object System.Windows.Forms.Label
$lblServer.Text = "Server (IP or Hostname):"
$lblServer.Location = New-Object System.Drawing.Point(20, 20)
$lblServer.Size = New-Object System.Drawing.Size(160, 20)
$lblServer.ForeColor = $textColor
$form.Controls.Add($lblServer)

$txtServer = New-Object System.Windows.Forms.TextBox
$txtServer.Location = New-Object System.Drawing.Point(190, 18)
$txtServer.Size = New-Object System.Drawing.Size(250, 22)
$txtServer.BackColor = $inputBg
$txtServer.ForeColor = $textColor
$txtServer.BorderStyle = "FixedSingle"
$form.Controls.Add($txtServer)

# --- Path ---
$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = "Remote Path:"
$lblPath.Location = New-Object System.Drawing.Point(20, 55)
$lblPath.Size = New-Object System.Drawing.Size(160, 20)
$lblPath.ForeColor = $textColor
$form.Controls.Add($lblPath)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(190, 53)
$txtPath.Size = New-Object System.Drawing.Size(250, 22)
$txtPath.Text = "/"
$txtPath.BackColor = $inputBg
$txtPath.ForeColor = $textColor
$txtPath.BorderStyle = "FixedSingle"
$form.Controls.Add($txtPath)

# --- Username ---
$lblUser = New-Object System.Windows.Forms.Label
$lblUser.Text = "Username:"
$lblUser.Location = New-Object System.Drawing.Point(20, 90)
$lblUser.Size = New-Object System.Drawing.Size(160, 20)
$lblUser.ForeColor = $textColor
$form.Controls.Add($lblUser)

$txtUser = New-Object System.Windows.Forms.TextBox
$txtUser.Location = New-Object System.Drawing.Point(190, 88)
$txtUser.Size = New-Object System.Drawing.Size(250, 22)
$txtUser.BackColor = $inputBg
$txtUser.ForeColor = $textColor
$txtUser.BorderStyle = "FixedSingle"
$form.Controls.Add($txtUser)

# --- Password ---
$lblPass = New-Object System.Windows.Forms.Label
$lblPass.Text = "Password:"
$lblPass.Location = New-Object System.Drawing.Point(20, 125)
$lblPass.Size = New-Object System.Drawing.Size(160, 20)
$lblPass.ForeColor = $textColor
$form.Controls.Add($lblPass)

$txtPass = New-Object System.Windows.Forms.TextBox
$txtPass.Location = New-Object System.Drawing.Point(190, 123)
$txtPass.Size = New-Object System.Drawing.Size(250, 22)
$txtPass.UseSystemPasswordChar = $true
$txtPass.BackColor = $inputBg
$txtPass.ForeColor = $textColor
$txtPass.BorderStyle = "FixedSingle"
$form.Controls.Add($txtPass)

# --- Loops ---
$lblLoops = New-Object System.Windows.Forms.Label
$lblLoops.Text = "Number of Tests:"
$lblLoops.Location = New-Object System.Drawing.Point(470, 20)
$lblLoops.Size = New-Object System.Drawing.Size(120, 20)
$lblLoops.ForeColor = $textColor
$form.Controls.Add($lblLoops)

$numLoops = New-Object System.Windows.Forms.NumericUpDown
$numLoops.Location = New-Object System.Drawing.Point(600, 18)
$numLoops.Size = New-Object System.Drawing.Size(80, 22)
$numLoops.Minimum = 1
$numLoops.Maximum = 1000
$numLoops.Value = 10
$numLoops.BackColor = $inputBg
$numLoops.ForeColor = $textColor
$form.Controls.Add($numLoops)

# --- Delay ---
$lblDelay = New-Object System.Windows.Forms.Label
$lblDelay.Text = "Delay (seconds):"
$lblDelay.Location = New-Object System.Drawing.Point(470, 55)
$lblDelay.Size = New-Object System.Drawing.Size(120, 20)
$lblDelay.ForeColor = $textColor
$form.Controls.Add($lblDelay)

$numDelay = New-Object System.Windows.Forms.NumericUpDown
$numDelay.Location = New-Object System.Drawing.Point(600, 53)
$numDelay.Size = New-Object System.Drawing.Size(80, 22)
$numDelay.Minimum = 0
$numDelay.Maximum = 60
$numDelay.Value = 2
$numDelay.BackColor = $inputBg
$numDelay.ForeColor = $textColor
$form.Controls.Add($numDelay)

# --- Mode ---
$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Text = "Mode:"
$lblMode.Location = New-Object System.Drawing.Point(470, 90)
$lblMode.Size = New-Object System.Drawing.Size(120, 20)
$lblMode.ForeColor = $textColor
$form.Controls.Add($lblMode)

$cmbMode = New-Object System.Windows.Forms.ComboBox
$cmbMode.Location = New-Object System.Drawing.Point(600, 88)
$cmbMode.Size = New-Object System.Drawing.Size(100, 22)
$cmbMode.DropDownStyle = "DropDownList"
$cmbMode.Items.AddRange(@("Passive", "Active"))
$cmbMode.SelectedIndex = 0
$cmbMode.BackColor = $inputBg
$cmbMode.ForeColor = $textColor
$form.Controls.Add($cmbMode)

# --- Retries ---
$lblRetries = New-Object System.Windows.Forms.Label
$lblRetries.Text = "Retries:"
$lblRetries.Location = New-Object System.Drawing.Point(470, 125)
$lblRetries.Size = New-Object System.Drawing.Size(120, 20)
$lblRetries.ForeColor = $textColor
$form.Controls.Add($lblRetries)

$numRetries = New-Object System.Windows.Forms.NumericUpDown
$numRetries.Location = New-Object System.Drawing.Point(600, 123)
$numRetries.Size = New-Object System.Drawing.Size(80, 22)
$numRetries.Minimum = 0
$numRetries.Maximum = 10
$numRetries.Value = 1
$numRetries.BackColor = $inputBg
$numRetries.ForeColor = $textColor
$form.Controls.Add($numRetries)

# --- Checkboxes ---
$chkIntegrity = New-Object System.Windows.Forms.CheckBox
$chkIntegrity.Text = "Integrity Check (download + hash)"
$chkIntegrity.Location = New-Object System.Drawing.Point(20, 165)
$chkIntegrity.Size = New-Object System.Drawing.Size(250, 22)
$chkIntegrity.ForeColor = $textColor
$form.Controls.Add($chkIntegrity)

$chkLog = New-Object System.Windows.Forms.CheckBox
$chkLog.Text = "Save log file"
$chkLog.Location = New-Object System.Drawing.Point(280, 165)
$chkLog.Size = New-Object System.Drawing.Size(120, 22)
$chkLog.Checked = $true
$chkLog.ForeColor = $textColor
$form.Controls.Add($chkLog)

# --- Buttons ---
$btnAbout = New-Object System.Windows.Forms.Button
$btnAbout.Text = "About"
$btnAbout.Location = New-Object System.Drawing.Point(690, 165)
$btnAbout.Size = New-Object System.Drawing.Size(70, 28)
$btnAbout.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$btnAbout.ForeColor = $textColor
$btnAbout.FlatStyle = "Flat"
$form.Controls.Add($btnAbout)

$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Text = "Load Config"
$btnLoad.Location = New-Object System.Drawing.Point(470, 165)
$btnLoad.Size = New-Object System.Drawing.Size(100, 28)
$btnLoad.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$btnLoad.ForeColor = $textColor
$btnLoad.FlatStyle = "Flat"
$form.Controls.Add($btnLoad)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Save Config"
$btnSave.Location = New-Object System.Drawing.Point(580, 165)
$btnSave.Size = New-Object System.Drawing.Size(100, 28)
$btnSave.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$btnSave.ForeColor = $textColor
$btnSave.FlatStyle = "Flat"
$form.Controls.Add($btnSave)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Test"
$btnStart.Location = New-Object System.Drawing.Point(20, 210)
$btnStart.Size = New-Object System.Drawing.Size(120, 35)
$btnStart.BackColor = $accentGreen
$btnStart.ForeColor = [System.Drawing.Color]::White
$btnStart.FlatStyle = "Flat"
$form.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop"
$btnStop.Location = New-Object System.Drawing.Point(150, 210)
$btnStop.Size = New-Object System.Drawing.Size(100, 35)
$btnStop.Enabled = $false
$btnStop.BackColor = $accentRed
$btnStop.ForeColor = [System.Drawing.Color]::White
$btnStop.FlatStyle = "Flat"
$form.Controls.Add($btnStop)

# --- Progress ---
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(270, 215)
$progress.Size = New-Object System.Drawing.Size(410, 25)
$form.Controls.Add($progress)

# --- Results ---
$lblResults = New-Object System.Windows.Forms.Label
$lblResults.Text = "Results:"
$lblResults.Location = New-Object System.Drawing.Point(20, 260)
$lblResults.Size = New-Object System.Drawing.Size(100, 20)
$lblResults.ForeColor = $textColor
$form.Controls.Add($lblResults)

$txtResults = New-Object System.Windows.Forms.RichTextBox
$txtResults.Location = New-Object System.Drawing.Point(20, 285)
$txtResults.Size = New-Object System.Drawing.Size(720, 370)
$txtResults.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtResults.ReadOnly = $true
$txtResults.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 25)
$txtResults.ForeColor = $textColor
$txtResults.BorderStyle = "FixedSingle"
$form.Controls.Add($txtResults)

# -------------------------------------------------
# Button Events (same logic as before + dark-friendly logging)
# -------------------------------------------------
$btnAbout.Add_Click({
    # Create a custom dark About form
    $aboutForm = New-Object System.Windows.Forms.Form
    $aboutForm.Text = "About FTP Load Test"
    $aboutForm.Size = New-Object System.Drawing.Size(460, 320)
    $aboutForm.StartPosition = "CenterParent"
    $aboutForm.FormBorderStyle = "FixedDialog"
    $aboutForm.MaximizeBox = $false
    $aboutForm.MinimizeBox = $false
    $aboutForm.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $aboutForm.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)

    # Title
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "FTP Load Test  v$ScriptVersion"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 180, 255)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 20)
    $lblTitle.Size = New-Object System.Drawing.Size(400, 30)
    $aboutForm.Controls.Add($lblTitle)

    # Description
    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = "A tool for testing FTP server reliability.`r`nEspecially useful for diagnosing intermittent`r`nScan-to-FTP / Scan-to-Folder issues on printers."
    $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblDesc.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $lblDesc.Location = New-Object System.Drawing.Point(20, 60)
    $lblDesc.Size = New-Object System.Drawing.Size(400, 60)
    $aboutForm.Controls.Add($lblDesc)

    # Website label
    $lblWeb = New-Object System.Windows.Forms.Label
    $lblWeb.Text = "Download the latest version from:"
    $lblWeb.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblWeb.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $lblWeb.Location = New-Object System.Drawing.Point(20, 130)
    $lblWeb.Size = New-Object System.Drawing.Size(400, 20)
    $aboutForm.Controls.Add($lblWeb)

    # Clickable link
    $lnkGithub = New-Object System.Windows.Forms.LinkLabel
    $lnkGithub.Text = "https://github.com/ScriptedBits/FTP-testing"
    $lnkGithub.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Underline)
    $lnkGithub.LinkColor = [System.Drawing.Color]::FromArgb(0, 180, 255)
    $lnkGithub.ActiveLinkColor = [System.Drawing.Color]::FromArgb(100, 200, 255)
    $lnkGithub.Location = New-Object System.Drawing.Point(20, 152)
    $lnkGithub.Size = New-Object System.Drawing.Size(400, 20)
    $lnkGithub.Add_Click({
        Start-Process "https://github.com/ScriptedBits/FTP-testing"
    })
    $aboutForm.Controls.Add($lnkGithub)

    # License
    $lblLicense = New-Object System.Windows.Forms.Label
    $lblLicense.Text = "MIT License`r`nCopyright (c) 2026 ScriptedBits"
    $lblLicense.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblLicense.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 160)
    $lblLicense.Location = New-Object System.Drawing.Point(20, 190)
    $lblLicense.Size = New-Object System.Drawing.Size(400, 40)
    $aboutForm.Controls.Add($lblLicense)

    # Close button
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(170, 240)
    $btnClose.Size = New-Object System.Drawing.Size(100, 30)
    $btnClose.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnClose.ForeColor = [System.Drawing.Color]::White
    $btnClose.FlatStyle = "Flat"
    $btnClose.Add_Click({ $aboutForm.Close() })
    $aboutForm.Controls.Add($btnClose)

    # Show the About window
    $aboutForm.ShowDialog() | Out-Null
})

$btnLoad.Add_Click({
    $configFile = Join-Path $PSScriptRoot "ftpconfig.ini"
    if (Test-Path $configFile) {
        $ini = Read-Ini -Path $configFile
        $txtServer.Text = $ini["FTP"]["Server"]
        $txtPath.Text   = $ini["FTP"]["Path"]
        $txtUser.Text   = $ini["FTP"]["Username"]
        $txtPass.Text   = $ini["FTP"]["Password"]
        $numLoops.Value = [int]$ini["FTP"]["Loops"]
        if ($ini["FTP"]["Delay"])   { $numDelay.Value = [int]$ini["FTP"]["Delay"] }
        if ($ini["FTP"]["Mode"])    { $cmbMode.SelectedItem = $ini["FTP"]["Mode"] }
        if ($ini["FTP"]["Retries"]) { $numRetries.Value = [int]$ini["FTP"]["Retries"] }
        if ($ini["FTP"]["IntegrityCheck"]) { $chkIntegrity.Checked = ($ini["FTP"]["IntegrityCheck"] -eq "True") }
        if ($ini["FTP"]["Log"]) { $chkLog.Checked = ($ini["FTP"]["Log"] -eq "True") }
        Write-Log "Configuration loaded from ftpconfig.ini" "DarkGreen"
    }
    else {
        [System.Windows.Forms.MessageBox]::Show("ftpconfig.ini not found.", "Info")
    }
})

$btnSave.Add_Click({
    $configFile = Join-Path $PSScriptRoot "ftpconfig.ini"
    Save-Ini -Path $configFile -Server $txtServer.Text -RemotePath $txtPath.Text `
             -Username $txtUser.Text -Password $txtPass.Text `
             -Loops ([int]$numLoops.Value) -Delay ([int]$numDelay.Value) `
             -Mode $cmbMode.SelectedItem -Retries ([int]$numRetries.Value) `
             -IntegrityCheck $chkIntegrity.Checked -LogEnabled $chkLog.Checked
    Write-Log "Configuration saved to ftpconfig.ini" "DarkGreen"
})

$btnStop.Add_Click({
    $script:StopRequested = $true
    Write-Log "Stop requested... waiting for current operation to finish." "DarkOrange"
})

$btnStart.Add_Click({
    $script:StopRequested = $false
    $btnStart.Enabled = $false
    $btnStop.Enabled = $true
    $btnLoad.Enabled = $false
    $btnSave.Enabled = $false
    $txtResults.Clear()
    $progress.Value = 0

    $server = $txtServer.Text.Trim()
    $path   = $txtPath.Text.Trim()
    $user   = $txtUser.Text.Trim()
    $pass   = $txtPass.Text
    $loops  = [int]$numLoops.Value
    $delay  = [int]$numDelay.Value
    $mode   = $cmbMode.SelectedItem
    $retries = [int]$numRetries.Value
    $integrityCheck = $chkIntegrity.Checked
    $logEnabled = $chkLog.Checked
    $usePassive = ($mode -eq "Passive")

    if ([string]::IsNullOrWhiteSpace($server) -or [string]::IsNullOrWhiteSpace($user)) {
        [System.Windows.Forms.MessageBox]::Show("Server and Username are required.", "Error")
        $btnStart.Enabled = $true
        $btnStop.Enabled = $false
        return
    }

    if (-not $path.StartsWith("/")) { $path = "/" + $path }
    if ($path -eq "/") { $path = "" }

    Write-Log "FTP Load Test v$ScriptVersion" "DarkBlue"
    Write-Log "Server: $server | Path: $($path -replace '^$','/') | Mode: $mode | Loops: $loops"
    Write-Log ""

    # DNS Check
    Write-Log "Running DNS Reliability Check (10 lookups)..." "DarkBlue"
    $dnsSuccess = 0
    $dnsFail = 0

    for ($d = 1; $d -le 10; $d++) {
        if ($script:StopRequested) { break }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $result = [System.Net.Dns]::GetHostAddresses($server)
            $sw.Stop()
            $ipList = ($result | ForEach-Object { $_.IPAddressToString }) -join ", "
            Write-Log "  Lookup $d : OK ($($sw.ElapsedMilliseconds)ms) @ $ipList" "DarkGreen"
            $dnsSuccess++
        }
        catch {
            $sw.Stop()
            Write-Log "  Lookup $d : FAILED ($($sw.ElapsedMilliseconds)ms) @ $($_.Exception.Message)" "Red"
            $dnsFail++
        }
        Start-Sleep -Milliseconds 150
    }

    Write-Log "DNS Results: $dnsSuccess successful / $dnsFail failed"
    if ($dnsFail -gt 1) {
        Write-Log "WARNING: DNS is unreliable! Prefer using an IP address." "Red"
    }
    Write-Log ""

    # Initial Connection Test
    Write-Log "Testing initial FTP connection..." "DarkBlue"
    $initial = Invoke-FtpCommand -Server $server -RemotePath $path `
                                 -Method ([System.Net.WebRequestMethods+Ftp]::ListDirectory) `
                                 -Username $user -Password $pass -UsePassive $usePassive

    if (-not $initial.Success) {
        Write-Log "ERROR: Cannot connect to the FTP server!" "Red"

        $errorDetails = $initial.Message
        if ([string]::IsNullOrWhiteSpace($errorDetails) -or $errorDetails -eq "Undefined") {
            $errorDetails = "Unable to connect to the FTP server (connection failed)"
        }
        Write-Log "Details: $errorDetails" "Red"

        if ($dnsFail -eq 10) {
            Write-Log "IMPORTANT: All 10 DNS lookups failed!" "Red"
            Write-Log "Use an IP address instead of a hostname." "Red"
        }
        else {
            Write-Log "Possible causes: wrong credentials, path, firewall, or FTP service not running." "DarkOrange"
        }

        $btnStart.Enabled = $true
        $btnStop.Enabled = $false
        $btnLoad.Enabled = $true
        $btnSave.Enabled = $true
        return
    }

    Write-Log "Initial FTP connection successful!" "DarkGreen"
    Write-Log ""

    # Create temp files
    $tempDir = Join-Path $env:TEMP "FTPTest_$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $sizes = @(
        @{ Name = "1KB"; Size = 1KB },
        @{ Name = "10KB"; Size = 10KB },
        @{ Name = "100KB"; Size = 100KB },
        @{ Name = "1MB"; Size = 1MB }
    )
    $testFiles = @()
    foreach ($s in $sizes) {
        $file = Join-Path $tempDir "test_$($s.Name).bin"
        $bytes = New-Object byte[] $s.Size
        (New-Object System.Random).NextBytes($bytes)
        [System.IO.File]::WriteAllBytes($file, $bytes)
        $testFiles += $file
    }

    $success = 0
    $failed = 0
    $startTime = Get-Date

    for ($i = 1; $i -le $loops; $i++) {
        if ($script:StopRequested) {
            Write-Log "Test stopped by user." "DarkOrange"
            break
        }

        $fileToUpload = $testFiles[($i - 1) % $testFiles.Count]
        $sizeName = (Split-Path $fileToUpload -Leaf) -replace "test_|\.bin",""
        $progress.Value = [math]::Round(($i / $loops) * 100)

        $attempt = 0
        $testSuccess = $false
        $finalMessage = ""
        $loginMs = 0
        $uploadMs = 0

        while ($attempt -le $retries -and -not $testSuccess -and -not $script:StopRequested) {
            $attempt++
            $attemptInfo = if ($attempt -gt 1) { " (Retry $($attempt-1))" } else { "" }

            Write-Log "[$i/$loops] $sizeName$attemptInfo ... "

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $loginResult = Invoke-FtpCommand -Server $server -RemotePath $path `
                                             -Method ([System.Net.WebRequestMethods+Ftp]::ListDirectory) `
                                             -Username $user -Password $pass -UsePassive $usePassive
            $sw.Stop()
            $loginMs = $sw.ElapsedMilliseconds

            if (-not $loginResult.Success) {
                $finalMessage = "LOGIN FAILED ($loginMs`ms) → $($loginResult.Message)"
                Write-Log $finalMessage "Red"
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
                Write-Log $finalMessage "Red"
                continue
            }

            $testSuccess = $true
            $finalMessage = "OK | Login ${loginMs}ms | Upload ${uploadMs}ms"
            Write-Log $finalMessage "DarkGreen"
        }

        if ($testSuccess) { $success++ } else { $failed++ }

        if ($i -lt $loops -and $delay -gt 0 -and -not $script:StopRequested) {
            Start-Sleep -Seconds $delay
        }
    }

    $duration = (Get-Date) - $startTime
    Write-Log ""
    Write-Log ("=" * 60)
    Write-Log "Finished in $([math]::Round($duration.TotalSeconds,1)) seconds"
    Write-Log "Successful : $success" "DarkGreen"
    Write-Log "Failed     : $failed" $(if ($failed -gt 0) {"Red"} else {"DarkGreen"})

    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    if ($logEnabled) {
        $logFile = Join-Path $PSScriptRoot "FTPTest_Log_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
        $txtResults.Text | Out-File -FilePath $logFile -Encoding UTF8
        Write-Log "Log saved to: $logFile" "DarkBlue"
    }

    $progress.Value = 100
    $btnStart.Enabled = $true
    $btnStop.Enabled = $false
    $btnLoad.Enabled = $true
    $btnSave.Enabled = $true
})

# Auto-load config if exists
$configFile = Join-Path $PSScriptRoot "ftpconfig.ini"
if (Test-Path $configFile) {
    $btnLoad.PerformClick()
}

[void]$form.ShowDialog()