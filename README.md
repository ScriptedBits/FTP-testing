[![GitHub Downloads](https://img.shields.io/github/downloads/ScriptedBits/FTP-testing/total?style=for-the-badge&color=blue)](https://github.com/ScriptedBits/FTP-testing/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207+-blue.svg?style=for-the-badge)](https://github.com/PowerShell/PowerShell)

A PowerShell tool (Console + GUI) for testing FTP server reliability...

# FTP Load Test Script

A PowerShell tool designed to thoroughly test FTP server reliability — especially useful for diagnosing intermittent **Scan to FTP** / **Scan to Folder** failures on printers (Kyocera, Ricoh, HP, Xerox, etc.).

---

## Features

- Full login → change directory → upload → logoff cycle (repeated)
- Configurable number of test loops
- Passive / Active mode support
- Automatic retries on failure
- Optional file integrity verification (SHA256)
- Detailed per-test timing (Login + Upload in milliseconds)
- DNS reliability check (detects flaky name resolution)
- Progress bar + live status
- Optional detailed logging to text file
- Creates dummy test files of different sizes (1KB → 1MB)
- Reads settings from `ftpconfig.ini` or prompts interactively

---

## Why this script exists

Many printers fail intermittently when scanning to FTP. Common root causes include:

- Unreliable DNS resolution (hostname works only part of the time)
- FTP server rate limiting / connection limits
- Passive mode / firewall issues
- Slow authentication on Windows IIS FTP
- Files being moved/deleted immediately after upload

This script helps isolate those problems quickly.

---

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Network access to the FTP server
- Execution policy that allows local scripts  
  (`Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`)

---

## Quick Start

1. Download `FtpLoadTest.ps1`
2. (Optional) Create `ftpconfig.ini` in the same folder
3. Run the script:

```powershell
.\FtpLoadTest.ps1
