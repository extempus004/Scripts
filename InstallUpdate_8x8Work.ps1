# 8x8 Work Update/Install
# Variables
$workingdir = "C:\TechMDWorking"
$msipath = "$workingdir\8x8.msi"
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
$appInfo = Get-ChildItem -Path $registryPath -Recurse | Get-ItemProperty | Where-Object { $_.DisplayName -like "*8x8 Work*" }
# Points to the 8x8 Work web page that lists all the download links
$manufacturerLink = Invoke-WebRequest -uri "https://support.8x8.com/business-phone/voice/work-desktop/download-8x8-work-for-desktop#MSI_for_Machine-Wide_Installation" -UseBasicParsing
# Listing all the .msi links available on their website
$msiLinks = $manufacturerLink.Links | Select-Object -ExpandProperty href -ErrorAction SilentlyContinue | Where-Object { $_ -like "*.msi" } | Sort-Object -Unique
# Parse's the list of URL's found to target the most recent version
$latestUrl = $msiLinks | Sort-Object -Property { [version](($_ -split 'v')[-1] -replace '(-|\.msi)', '') } -Descending | Select-Object -First 1
# Get the latest version number
$desiredVersion = if ($latestUrl -match 'v(\d+\.\d+\.\d+-\d+)') { $matches[1] } else { "Version not found" }

function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

function PrepDirectory {
    if (!(Test-Path $workingdir)) {
        Write-Output "$(Get-TimeStamp) Creating $workingdir..."
        New-Item $workingdir -Force
    }
    
    # Download the MSI file
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Output "$(Get-TimeStamp) Downloading the file..."
    Invoke-WebRequest -Uri $latestURL -OutFile $msipath
    
    if (Test-Path $msipath) {
        Write-Output "$(Get-TimeStamp) File downloaded successfully."
    }
    else {
        Write-Error "File download failed."
    }
}

function Install8x8 {
    Write-Output "$(Get-TimeStamp) Running installer..."
    Start-Process msiexec.exe -ArgumentList "/i `"$msipath`" /norestart /passive /qb" -Wait # Must be run as SYSTEM for slient install - /qn
}

# Checking for installed version
if ($appInfo) {
    foreach ($version in $appInfo) {
        $installedVersion = $version.DisplayVersion

        # Convert installed version to the same format by replacing '-' with '.'
        $desiredVersion = $desiredVersion -replace '-', '.'

        if ([version]$installedVersion -lt [version]$desiredVersion) {
            Write-Output "$(Get-TimeStamp) Installed 8x8 Work Version $($installedVersion) is lower than the desired version $($desiredVersion), updating..."
            PrepDirectory
            Install8x8
        }
        else {
            Write-Output "$(Get-TimeStamp) Installed 8x8 Work Version $($installedVersion) meets or exceeds the desired version $($desiredVersion)."
            Exit
        }
    }
}
else {
    Write-Output "$(Get-TimeStamp) 8x8 Work not found, installing..."
    PrepDirectory
    Install8x8
}

# Checking for installed version
$appInfo = Get-ChildItem -Path $registryPath -Recurse | Get-ItemProperty | Where-Object { $_.DisplayName -like "*8x8 Work*" }
if ($appInfo) {
    foreach ($version in $appInfo) {
        $installedVersion = [System.Version]$version.DisplayVersion
        Write-Output "$(Get-TimeStamp) Installed 8x8 Work Version $($installedVersion)."
        Remove-Item $msipath -Force -ErrorAction SilentlyContinue
    }
}
