<#
    Used in conjunction with the ForceRebootAfter2Hour script in the RMM repository.
    Will check updatime and delete the scheduled reboot task if recently rebooted.
#>
$bootuptime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
$CurrentDate = Get-Date
$uptime = $CurrentDate - $bootuptime
$daysuptime = $($uptime.Days)
$taskRebootName = "Scheduled Reboot"
    
if ($daysuptime -le 14) {
    if (Get-ScheduledTask -TaskName $taskRebootName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskRebootName -Confirm:$false
    }
}