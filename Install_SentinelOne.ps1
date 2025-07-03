<#
.SYNOPSIS
    Installs the SentinelOne agent.

.DESCRIPTION
    This script automates the download, installation, and verification of the SentinelOne agent.

.PARAMETER siteToken
    Required. The SentinelOne site token used for installation. By default, pulls from a pre-defined variable in CW RMM.

.PARAMETER workingdir
    Optional. Working directory for file operations. Default is C:\TechMDWorking

.NOTES
    Author   : ctaylor
    Created  : 07/09/2024
    Version  : 3.0

.VERSION HISTORY
    3.3 (07/03/2025) - ctaylor
        - Added legacy download backup
    3.2 (07/02/2025) - ctaylor
        - Added better Error reporting for CW RMM, using Write-Error in place of throw
    3.1 (06/30/2025) - ctaylor
        - Using SP hosted installers since the "latest" from CW is not up to date  
        - Moved exit codes to install function
    3.0 (06/30/2025) - ctaylor
        - Changed download logic to use .NET HttpClient
        - Added internal logging function
        - Changed to exe installer per S1 recommendation for 22.1+
        - Changed install URLs per CW recommendation
        - https://update2.itsupport247.net/SentinelOne/sentinelone_latest/SentinelOneInstaller_windows_x64.exe (replace with 86 for 32bit)
    2.2 - ctaylor
        - Adjusted exit codes
    2.1 - ctaylor
        - Re-added cleanup logic
        - Added safety check for workingdir being a file
    2.0 - ctaylor
        - Modularized script into functions
        - Added additional validation
    1.3 (07/31/2024) - ctaylor
        - Fixed installation check logic
    1.2 (07/30/2024) - ctaylor
        - Added return if site token is missing
    1.1 (07/09/2024) - ctaylor
        - Moved variables to the top
        - Added /norestart to installer
        - Switched success check to use Registry
#>
[CmdletBinding()]
param (
    [Parameter()]
    [String]$S1SiteToken = "@S1SiteToken@",
    [String]$workingdir = "C:\TechMDWorking",
    [String]$logName = "SentinelOne"
)

# Generate timestamp (called when needed)
function Get-TimeStamp {
    return "`n[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

function Log {
    param([string]$Message)
    $entry = "$(Get-TimeStamp) $Message"
    Add-Content -Path $logFile -Value $entry
    if (-not $Quiet) {
        Write-Output "`n$entry"
    }
}

# Checking for Site Token
if ($S1SiteToken -eq "N/A") {
    $msg = "No site token set, exiting."
    Log $msg
    throw $msg
}

# Setup log file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $workingDir "$($logName)_$($timestamp).log"

# Cleanup old logs
Get-ChildItem -Path $workingDir -Filter "$($logName)*.log" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force -ErrorAction SilentlyContinue

# Define working directory
if (Test-Path $workingDir) {
    if ((Get-Item $workingDir).Attributes -notmatch 'Directory') {
        Remove-Item $workingDir -Force
        $null = New-Item -Path $workingDir -ItemType Directory
        Log "Working directory was not correctly configured. Remaking working directory."
    }
}
else {
    $null = New-Item -Path $workingDir -ItemType Directory
    Log "Working directory did not exist. Creating working directory."
}

function legacyDownloadFile {
    try {
        Log "Starting download with WebRequest..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadURL -OutFile $OutFile -UseBasicParsing
        Log "Downloaded: $OutFile"
        Install-S1
        return
    }
    catch {
        throw "Download failed: $downloadURL - $_"
    }
}

function Download-File {
    param (
        [int]$TimeoutSec = 60
    )
    try {
        Log "Starting download with HttpClient..."
        Add-Type -AssemblyName System.Net.Http
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)

        $response = $client.GetAsync($downloadURL).Result

        if (-not $response) {
            $statusCode = if ($response -and $response.StatusCode) { $response.StatusCode.value__ } else { 'Unknown' }
            $reason = if ($response -and $response.ReasonPhrase) { $response.ReasonPhrase } else { 'No reason provided.' }
            Log "HTTP failure: $statusCode - $reason. Falling back to legacy download."
            legacyDownloadFile
            return
        }
        
        Log "StatusCode: $($response.StatusCode) | Content Length: $($response.Content.Headers.ContentLength)"

        $bytes = $response.Content.ReadAsByteArrayAsync().Result
        [System.IO.File]::WriteAllBytes($OutFile, $bytes)

        if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) {
            Log "Downloaded successfully to $OutFile"
            Install-S1
        }
        else {
            Log "Downloaded file is empty or failed to write. Falling back to legacy download."
            legacyDownloadFile
        }
    }
    catch {
        $msg = $_.Exception.Message
        if ($_.Exception.InnerException) {
            $msg += " | Inner: $($_.Exception.InnerException.Message)"
        }
        Log "Download failed: $msg. Falling back to legacy download."
        legacyDownloadFile
    }
}
function Install-S1 {
    try {
        Log "Running installer..."

        & "$OutFile" --dont_fail_on_config_preserving_failures -q -t "$S1SiteToken"
        $exitcode = $LastExitCode
        Log "Exit code is $exitcode."

        switch ($exitCode) {
            0 { Write-Output "$(Get-TimeStamp) Installation successful." }
            1 { Write-Output "$(Get-TimeStamp) Installation successful." }
            3010 { Write-Output "$(Get-TimeStamp) Installation successful. Reboot required." }
            1603 { Write-Error "$(Get-TimeStamp) Fatal error during installation."; exit }
            1663 { Write-Error "$(Get-TimeStamp) Fatal error during installation."; exit }
            1619 { Write-Error "$(Get-TimeStamp) MSI file not found or invalid."; exit }
            100 { Write-Error "$(Get-TimeStamp) The uninstall of the previous Agent succeeded. Reboot the endpoint to continue with the installation of the new Agent."; exit }
            103 { Write-Error "$(Get-TimeStamp) Reboot is required to uninstall the previous Agent and install the new Agent."; exit }
            104 { Write-Error "$(Get-TimeStamp) Reboot is already required by a previous run of the installer."; exit }
            2009 { Write-Error" Failed to retrieve the Agent UID for upgrade. An Agent with the same or higher version is already installed on the endpoint.`nPlease run uninstaller first.": exit }
            1000 { Write-Error "$(Get-TimeStamp) Upgrade canceled. Cannot continue with the upgrade. An Agent with the same or higher version is already installed on the endpoint.`nPlease run uninstaller first."; exit }
            default { Write-Error "$(Get-TimeStamp) Unexpected exit code: $exitCode`n" }
        }
    }
    catch {
        Write-Error "$(Get-TimeStamp) Failed to run installer: $_"
    }
}

### Start Script Runbook
# Check OS Architecture
$osArchitecture = (Get-WmiObject win32_operatingsystem).osarchitecture
if ($osArchitecture -like "*ARM 64-bit Processor*") { 
    $OutFile = "$workingdir\SentinelOneInstaller_windows_ARM64_v24_1_5_277.exe"
    $DownloadURL = "https://icsnewyork.sharepoint.com/:u:/s/RMMScriptAdmins/EdrIYEl-A8BGjjcEbcwShxYBY-mXNDFAyu3raQNWaz7qvQ?e=j1qX2k&download=1"
    Log "Set ARM 64 variables."
}
elseif ($osArchitecture -like "*64*") {
    $OutFile = "$workingdir\SentinelOneInstaller_windows_64bit_v24_2_3_471.exe"
    $DownloadURL = "https://icsnewyork.sharepoint.com/:u:/s/RMMScriptAdmins/Ec8drRQNpt5HgZRD_wsQGPsBi149ohKHpjWOiX_yZhX7Cw?e=7AtNEe&download=1"
    Log "Set 64-bit variables."
}
elseif ($osArchitecture -like "*32*") {
    $OutFile = "$workingdir\SentinelOneInstaller_windows_32bit_v23_4_6_347.exe"
    $DownloadURL = "https://icsnewyork.sharepoint.com/:u:/s/RMMScriptAdmins/Efiq-66DneZMgrIt8n3tjSQBSiHtJtA-AzaTZUWK82t-ww?e=dwsKW7&download=1"
    Log "Set 32-bit variables."
}
else {
    Log "Unknown architecture."
    Write-Error "$(Get-TimeStamp) Unknown architecture."
}

if (-not (Test-Path $OutFile)) {
    Download-File
}
else {
    Log "Installer found, skipping download..."
    Install-S1
}

#Cleanup
Remove-Item $OutFile -Force -ErrorAction SilentlyContinue