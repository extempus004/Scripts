# Trigger Reboot Prompt

# Christian Taylor
# TechMD
# 03/01/24

param (
    [Parameter()]
    [String]$WorkingDir = "C:\TechMDWorking",
    [Parameter()]
    [String]$PSFile_URL = "fake.url",
    [Parameter()]
    [String]$PSFile_Path = "$workingdir\ForceRebootAfter2Hour.ps1",
    [Parameter()]
    [String]$LogoURL = "fake.url",
    [Parameter()]
    [String]$LogoPath = "$workingdir\TechMD-Logo.png",
    [Parameter()]
    [String]$FaviconURL = "fake.url",
    [Parameter()]
    [String]$FaviconPath = "$workingdir\TechMD-Favicon.png",
    [Parameter()]
    [String]$taskRebootName = "Scheduled Reboot",
    [Parameter()]
    [String]$taskUptimeName = $taskUptimeName,
    [Parameter()]
    [DateTime]$taskDelay = (Get-Date).AddSeconds(6900), #Scheduled task will run 2 hours from script execution
    [Parameter()]
    [DateTime]$checkTime = (Get-Date).AddSeconds(6600),
    [Parameter()]
    [Int]$rebootDelay = 300, # 5 minute reboot delay
    [Parameter()]
    [String]$UptimeScriptURL = "fake.url",
    [Parameter()]
    [String]$UptimeScriptPath = "$workingdir\LastCheck.ps1",
    [Parameter()]
    [String]$Company = "TechMD"
)

# Generate timestamp (called when needed)
function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

# See if anyone is currently logged in (we only want to continue if it's either not logged in, or logged in but locked)
function InitiateScript {
    if ((Get-CimInstance -ClassName Win32_OperatingSystem).ProductType -eq 1 ) {
        Write-Output "$(Get-TimeStamp) Checking Kiosk Mode..."
        CheckKiosk # Checks to make sure the agent isn't in Kiosk mode
    }
    
    Write-Output "$(Get-TimeStamp) Checking logon state of target endpoint..."
    $explorer = Get-Process | Where-Object { $_.ProcessName -eq "Explorer" } # Use presence of explorer.exe as indication of use
    $logonui = Get-Process | Where-Object { $_.ProcessName -eq "logonui" } # Use presence of LogonUI.exe as indication of lock

    if ($null -ne $explorer -and $null -eq $logonui) {
        Write-Output "$(Get-TimeStamp) This endpoint is logged in and unlocked (in use)"

        #Write-Output "$(Get-TimeStamp) Checking Uptime..."
        #CheckUptime # Ends the script if uptime <= 2 days

        #Write-Output "$(Get-TimeStamp) Checking Reboot Required..."
        #CheckPendingReboot # Ends the script if reboot required flag doesn't exist
        
        Write-Output "$(Get-TimeStamp) Prepping Directory..."
        PrepDirectory # Delete any past remnants of this script
        
        Write-Output "$(Get-TimeStamp) Checking PS Version..."
        CheckPSVersion # Determine PowerShell supported cmdlets
        
        Write-Output "$(Get-TimeStamp) Downloading Files..."
        DownloadPS1 # A prompt is needed, so we build the PS1 file that will generate the prompt
        
        Write-Output "$(Get-TimeStamp) Setting Permissions..."
        SetPermissions # Standard users (non-admins) cannot see the message box unless permissions are given
        
        Write-Output "$(Get-TimeStamp) Creating Scheduled Task..."
        CreateScheduledTask # Now immediately call the PS1 file we just created as a scheduled task so that the user can see it

        Write-Output "$(Get-TimeStamp) Creating Shut Down Task..."
        CreateRebootTask

        TaskRebootCheck

        Write-Output "$(Get-TimeStamp) Getting Results..."
        GetResults # Cleanup and end script

        Write-Output "$(Get-TimeStamp) Fin."
    }
    else {
        Write-Output "$(Get-TimeStamp) No user is logged in, rebooting..."
        Restart-Computer -Force
        Exit
    }
}

function PrepDirectory {
    Write-Output "$(Get-TimeStamp) Checking for directory: '$workingdir'..."
  
    # Create output directory if it does not already exist
    if (-not (Test-Path $workingdir -PathType Container)) {
        Write-Output "$(Get-TimeStamp) Creating '$workingdir'..."
        New-Item -ItemType Directory -Force -Path $workingdir -ErrorAction Stop | Out-Null
    }     
    if (Test-Path $workingdir -PathType Container) {
        Write-Output "$(Get-TimeStamp) Directory '$workingdir' exists."
    }
    $taskRebootExists = Get-ScheduledTask -TaskName $taskRebootName -ErrorAction SilentlyContinue
    if ($taskRebootExists) {
        Write-Output "$(Get-TimeStamp) Scheduled task $taskRebootName found. Deleting..."
        Unregister-ScheduledTask -TaskName $taskRebootName -Confirm:$false
    }
    $taskUptimeExists = Get-ScheduledTask -TaskName $taskUptimeName -ErrorAction SilentlyContinue
    if ($taskUptimeExists) {
        Write-Output "$(Get-TimeStamp) Scheduled task Check Uptime found. Deleting..."
        Unregister-ScheduledTask -TaskName $taskUptimeName -Confirm:$false
    }
}

function CheckPSVersion {
    Write-Output "$(Get-TimeStamp) Checking limitations of current PowerShell version..."
    $PSVersion = (Get-Variable PSVersionTable -ValueOnly).PSVersion.ToString()
    [version] $min = "3.1" # Greater than this, then it's legacy
    [version] $max = "5.1.15" # Less than or equal to this, then it's legacy
  
    if ($PSVersion -ge [System.Version]$min -and $PSVersion -le [System.Version]$max) {
        $script:legacy = $true
        Write-Output "$(Get-TimeStamp) WARNING: PowerShell v$PSVersion does not support Task Scheduler cmdlets. Continuing with legacy cmdlets."
    }
    elseif ($PSVersion -ge "1.0" -and $PSVersion -le "3.0") {
        throw "$(Get-TimeStamp) ERROR: PowerShell $PSVersion does not support the cmdlets required by this script. Upgrade PowerShell and try again."
    }
    else {
        Write-Output "$(Get-TimeStamp) This endpoint is running a fully supported version of PowerShell - OK!"
    }
}

# Downloads our custom .PS1 file and supporting images, which is the file responsible for showing our branded reboot prompt to the logged in user
function DownloadPS1 {
    Write-Output "$(Get-TimeStamp) Attempting to download files..."

    if (-not (Test-Path $LogoPath)) {
        # File doesn't exist, create it
        Invoke-WebRequest -Uri $LogoURL -OutFile $LogoPath
        Write-Output "$(Get-TimeStamp) File created: $LogoPath"
    }
    else {
        Write-Output "$(Get-TimeStamp) File already exists: $LogoPath"
    }

    if (-not (Test-Path $FaviconPath)) {
        # File doesn't exist, create it
        Invoke-WebRequest -Uri $FaviconURL -OutFile $FaviconPath
        Write-Output "$(Get-TimeStamp) File created: $FaviconPath"
    }
    else {
        Write-Output "$(Get-TimeStamp) File already exists: $FaviconPath"
    }

    if (-not (Test-Path $PSFile_Path)) {
        # File doesn't exist, create it
        Invoke-WebRequest -Uri $PSFile_URL -OutFile $PSFile_Path
        Write-Output "$(Get-TimeStamp) File created: $PSFile_Path"
    }
    else {
        Write-Output "$(Get-TimeStamp) Deleting and downloading new file: $PSFile_Path"
        Remove-Item $PSFile_Path -Force
        Invoke-WebRequest -Uri $PSFile_URL -OutFile $PSFile_Path
        Write-Output "$(Get-TimeStamp) File created: $PSFile_Path"
    }

    if (-not (Test-Path $UptimeScriptPath)) {
        # File doesn't exist, create it
        Invoke-WebRequest -Uri $UptimeScriptURL -OutFile $UptimeScriptPath
        Write-Output "$(Get-TimeStamp) File created: $UptimeScriptPath"
    }
    else {
        Write-Output "$(Get-TimeStamp) Deleting and downloading new file: $UptimeScriptPath"
        Remove-Item $UptimeScriptPath -Force
        Invoke-WebRequest -Uri $UptimeScriptURL -OutFile $UptimeScriptPath
        Write-Output "$(Get-TimeStamp) File created: $UptimeScriptPath"
    }
}

# Non-local admins are unable to see the BurntToast notification unless they have control over the working directory
function SetPermissions {
    $unlockme = $workingdir
    $acl = Get-ACL $unlockme
    $accessrule = New-Object System.Security.AccessControl.FileSystemAccessRule("everyone", "FullControl", "ContainerInherit,Objectinherit", "none", "Allow")
    $acl.AddAccessRule($accessrule)
    Set-Acl $unlockme $acl
    Write-Output "$(Get-TimeStamp) Permissions...OK!"
}

function CreateScheduledTask {
    if ($legacy) {
        Write-Output "$(Get-TimeStamp) Launching 'ForcedRebootPrompt.ps1' as current user via ((legacy)) Scheduled Tasks."
        try {
            # Win 8.1 and earlier have no cmdlets to delete tasks, thus each task must contain the current date, so not to risk duplication errors
            $runday = (Get-Date).AddSeconds(60).ToString("MM/dd/yyyy")
            $runtime = (Get-Date).AddSeconds(60).ToString("HH:mm:ss")
            $user = (Get-CimInstance –ClassName Win32_ComputerSystem | Select-Object -expand UserName)
            $taskname = "PromptForReboot_" + $runday.replace("/", "-") + $runtime.replace(":", "") # / is not a valid character in task name
            schtasks /create /sc once /tn $taskname /tr "PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Minimized -File $PSFile_Path -LogoPath $LogoPath -IconPath $FaviconPath -ApplicationID $Company -RestartReminder" /sd $runday /st $runtime /ru $user | Out-Null
            Write-Output "$(Get-TimeStamp) Task Created...OK!"
            New-Item "$workingdir\finished.flag"
        }
        catch {
            throw "$(Get-TimeStamp) ERROR: Unable to create scheduled task!"
        }
    }
    else {
        Write-Output "$(Get-TimeStamp) Launching 'ForcedRebootPrompt.ps1' as current user via Scheduled Tasks."
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Minimized -File $PSFile_Path -LogoPath $LogoPath -IconPath $FaviconPath -ApplicationID $Company -RestartReminder"
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date)
        $UserId = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty UserName)
        if (-not $UserId) {
            throw "UserId is null or empty"
        }
        $principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal
        Register-ScheduledTask PromptForReboot -InputObject $task | Out-Null
        Start-ScheduledTask -TaskName PromptForReboot
        Start-Sleep -Seconds 30
        New-Item "$workingdir\finished.flag"
    }
}

function CreateRebootTask {   
    $taskReboot = New-ScheduledTaskAction -Execute 'Shutdown' -Argument "/f /r /t $rebootDelay"
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount
    $taskTrigger = New-ScheduledTaskTrigger -At $taskDelay -Once
    
    Register-ScheduledTask -Action $taskReboot -Trigger $taskTrigger -Principal $taskPrincipal -taskName $taskRebootName

    Write-Output "$(Get-TimeStamp) Warning and Reboot scheduled."
}

function TaskRebootCheck {
    #Checks if the user manually rebooted before the task could run, cleans up reboot task if so
    $taskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$UptimeScriptPath`""
    $taskTrigger = New-ScheduledTaskTrigger -At $checkTime -Once
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount

    Register-ScheduledTask -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -taskName $taskUptimeName
}

function CheckUptime {
    $bootuptime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $CurrentDate = Get-Date
    $uptime = $CurrentDate - $bootuptime
    $uptime
    $daysuptime = $($uptime.Days)
    if ( $daysuptime -le 14 ) {
        Write-Output "$(Get-TimeStamp) Uptime within 14 days... Exiting."
        Exit
    }
}

function CheckPendingReboot {
    # Define registry paths that could indicate a pending reboot
    $rebootFlags = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SOFTWARE\Microsoft\Updates\UpdateExeVolatile",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
    )
  
    # Assume no reboot is needed initially
    $rebootNeeded = $false
  
    # Check each path and see if any reboot flags are present
    foreach ($path in $rebootFlags) {
        if (Test-Path $path) {
            Write-Output "$(Get-TimeStamp) A pending reboot flag found at $path"
            $rebootNeeded = $true
            break
        }
    }
  
    # Check the UpdateExeVolatile flag value if the key exists and no flag has been found yet
    if (-not $rebootNeeded) {
        $updateExeVolatile = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Updates" -Name "UpdateExeVolatile" -ErrorAction SilentlyContinue
        if ($updateExeVolatile -and $updateExeVolatile.UpdateExeVolatile -eq 3) {
            Write-Output "$(Get-TimeStamp) A pending reboot flag found in UpdateExeVolatile"
            $rebootNeeded = $true
        }
    }
  
    # If no reboot flags are found, exit the script
    if (-not $rebootNeeded) {
        Write-Output "$(Get-TimeStamp) No pending reboot flags found. Exiting script."
        exit
    }
  
    # If the script reaches this point, a reboot is pending
    Write-Output "$(Get-TimeStamp) Reboot required. Continuing with script execution."
}

# Stand by whilst waiting for user response
function GetResults {
    while (!(Test-Path "$workingdir\finished.flag")) { Start-Sleep 10 } # Loop, waiting for "finished.flag" to exist; created by the .PS1 script
    Remove-Item "$workingdir\finished.flag" -ErrorAction SilentlyContinue
    Remove-Item "$PSFile_Path" -ErrorAction SilentlyContinue
    Remove-Item "$LogoPath" -ErrorAction SilentlyContinue
    Remove-Item "$FaviconPath" -ErrorAction SilentlyContinue
    Write-Output "$(Get-TimeStamp) Script Completed OK!"
}

# Check to see if necessary Modules are installed. Installs if not, then imports them.
function InstallDependencies {
    # Check if NuGet module is installed
    if (-not (Get-Module -Name NuGet -ListAvailable)) {
        # Module not installed, so install it
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
        Write-Output "$(Get-TimeStamp) NuGet module has been installed."
    }
    else {
        Import-Module NuGet
        Write-Output "$(Get-TimeStamp) NuGet module has been imported."
    }
    
    # Checking if ToastReboot:// protocol handler is present
    try {
        New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -ErrorAction SilentlyContinue | Out-Null
        $ProtocolHandler = Get-Item 'HKCR:\ToastReboot'-ErrorAction SilentlyContinue
        Write-Output "$(Get-TimeStamp) Protocol handler set."
    }
    catch {
        Write-Output "$(Get-TimeStamp) Error encountered: $_"
    }
    
    # Installing ToastReboot:// protocol handler
    if (!$ProtocolHandler) {
        # Create handler for reboot
        New-item 'HKCR:\ToastReboot' -force
        set-itemproperty 'HKCR:\ToastReboot' -name '(DEFAULT)' -value 'url:ToastReboot' -force
        set-itemproperty 'HKCR:\ToastReboot' -name 'URL Protocol' -value '' -force
        new-itemproperty -path 'HKCR:\ToastReboot' -propertytype dword -name 'EditFlags' -value 2162688
        New-item 'HKCR:\ToastReboot\Shell\Open\command' -force
        set-itemproperty 'HKCR:\ToastReboot\Shell\Open\command' -name '(DEFAULT)' -value 'C:\Windows\System32\shutdown.exe -r -t 00' -force
        Write-Output "$(Get-TimeStamp) Reboot handlers have been set."
    }
    else {
        Write-Output "$(Get-TimeStamp) Protocal Handler: $ProtocolHandler"
    }
}

# Check to see if the computer is in Kiosk mode, if yes then exit script
function CheckKiosk {
    $ErrorActionPreference = "SilentlyContinue"
    # Check #1
    try {
        # Get the assigned access configuration
        $assignedAccess = Get-AssignedAccess
        
        # Check if there is any configuration present
        if ($assignedAccess) {
            Write-Output "$(Get-TimeStamp) The machine is in Kiosk Mode."
            Exit
        }
        else {
            Write-Output "$(Get-TimeStamp) The machine is not in Kiosk Mode."
        }
    }
    catch {
        Write-Error "An error occurred while checking for Kiosk Mode: $_"
    }
    
    # Check #2
    $KioskModeRegKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System\EnableLUA"
    
    if (Test-Path $KioskModeRegKey) {
        #Read the registry key
        $KioskModeValue = (Get-ItemProperty -Path $KioskModeRegKey).EnableLUA

        #Check if the value is set to 0
        if ($KioskModeValue -eq 0) {
            Write-Output "$(Get-TimeStamp) Kiosk mode is enabled"
            Exit
        }
        else {
            Write-Output "$(Get-TimeStamp) Kiosk mode is not enabled"
        }
    }
    else {
        Write-Output "$(Get-TimeStamp) Kiosk mode is not enabled"
    }
}

InitiateScript # Initiate function sequence