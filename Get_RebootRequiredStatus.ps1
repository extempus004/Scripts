<#
Version 1.3
- Date: 10/24/24
- Seperated check for PendingFileRenameOperations

Version 1.2
- Date: 10/15/24
- Added check for PendingFileRenameOperations
- Added check for Sophos Reboot Required

Version 1.1
- Date: 7/24/24
- Changed PendingFileRename operation to check for value
- Removed duplicate $false output at the end
#>

$ErrorActionPreference = "SilentlyContinue"

# Generate timestamp (called when needed)
function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

# Define all known registry paths that could indicate a pending reboot (exists only, specific value checks used later)
$rebootFlags = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\RebootRequired",
    "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\PendingComputerName"
)

# Assume no reboot is needed initially
$rebootRequired = $false

# Check each path and see if any above reboot flags are present
foreach ($path in $rebootFlags) {
    try {
        if (Test-Path $path) {
            Write-Output "$(Get-TimeStamp) A pending reboot flag found at $path"
            $rebootRequired = $true
            Write-Output "$(Get-TimeStamp) Reboot required: $rebootRequired"
            Return
        }
    }
    catch {
        Write-Error "Error accessing $_"
    }
}

# Check the UpdateExeVolatile flag value
try {
    $updateExeVolatile = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Updates" -Name "UpdateExeVolatile"
    if ($updateExeVolatile -and $updateExeVolatile.UpdateExeVolatile -eq 3) {
        Write-Output "$(Get-TimeStamp) A pending reboot flag found in UpdateExeVolatile"
        $rebootRequired = $true
        Write-Output "$(Get-TimeStamp) Reboot required: $rebootRequired"
        Return
    }
}
catch {
    Write-Error "Error accessing UpdateExeVolatile: $_"
}

# Check PendingFileRenameOperations
if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager") {
    $pendingFileRename = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations"
    if ($pendingFileRename.PendingFileRenameOperations) {
        Write-Output "$(Get-TimeStamp) PendingFileRenameOperations indicates a reboot is required."
        $rebootRequired = $true
        Write-Output "$(Get-TimeStamp) Reboot required: $rebootRequired"
        Return
    }
}

# Additional check for Sophos Reboot Required flag
$sophosRegistryPath = "HKLM:\SOFTWARE\WOW6432Node\Sophos\AutoUpdate\UpdateStatus\VolatileFlags"

try {
    if (Test-Path $sophosRegistryPath) {
        $sophosFlags = Get-ItemProperty -Path $sophosRegistryPath
        
        if ($sophosFlags.RebootRequired -eq 1) {
            Write-Output "$(Get-TimeStamp) Sophos indicates that a reboot is required."
            $rebootRequired = $true
            Write-Output "$(Get-TimeStamp) Reboot required: $rebootRequired"
            Return
        }
        
        if ($sophosFlags.UrgentRebootRequired -eq 1) {
            Write-Output "$(Get-TimeStamp) Sophos indicates that an urgent reboot is required."
            $rebootRequired = $true
            Write-Output "$(Get-TimeStamp) Reboot required: $rebootRequired"
            Return
        }
    }
    else {
        Write-Output "$(Get-TimeStamp) Sophos registry path not found."
    }
}
catch {
    Write-Error "Error accessing Sophos flags: $_"
}

# Final Result
Write-Output "$(Get-TimeStamp) Reboot required: $rebootRequired"