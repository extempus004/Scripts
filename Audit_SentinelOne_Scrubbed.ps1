<#
.SYNOPSIS
    Compare agents in SentinelOne | ConnectWise RMM | Domain OU for reconciliation. Searching for mismatches.

.DESCRIPTION
    S1 → grabs all computers from a site using the API
    CW RMM → using their logic
    Domain → PowerShell on the DC - Last checkin-in within 30 days

.REQUIREMENTS
    Requires CW RMM API Key to have devices.read, companies.read, and asset.read rights.
    $baseURL must be adjusted to unique console URL. Line 77 and 40.

.NOTES
    Author: Christian Taylor
    Created: 2025-06-26
    Version: 1.0

#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string]$clientName = "XYZ",
    [string]$workingdir = "C:\Working"
)

function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

$clientName = Read-Host "Enter the client name"
$S1ApiToken = Read-Host "Enter your Sentinel One API Token" -AsSecureString
$RMMApiId = Read-Host "Enter your CW RMM API ID" -AsSecureString
$RMMApiSecret = Read-Host "Enter your CW RMM API Token Secret" -AsSecureString

if (Test-Path $workingDir) {
    if ((Get-Item $workingDir).Attributes -notmatch 'Directory') {
        Remove-Item $workingDir -Force
        $null = New-Item -Path $workingDir -ItemType Directory
        Write-Output "Working directory was not correctly configured. Remaking working directory."
    }
} else {
    $null = New-Item -Path $workingDir -ItemType Directory
    Write-Output "Working directory did not exist. Creating working directory."
}

function Get-S1APIDevices {
    param (
        [System.Security.SecureString]$S1ApiTokenSecure,
        [string]$baseURL = "https://<your-instance-name>/web/api/v2.1" # Replace <your-instance-name> with your unique console URL.
    )
    $S1Token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($S1ApiTokenSecure))
    [hashtable]$Headers = @{
        "Authorization" = "ApiToken $S1Token"
        "Content-Type"  = "application/json"
    }
    try {
        $encodedClientName = [System.Web.HttpUtility]::UrlEncode($clientName) # Accounting for special characters
        $getSites = Invoke-RestMethod -Method GET -Uri "$BaseUrl/sites?name=$encodedClientName" -Headers $Headers
        $siteID = $getSites.data.sites.id
    }
    catch {
        Write-Error "Something went wrong when trying to retrieve site names: $_"
        return $null
    }
    try {
        $getAgents = Invoke-RestMethod -Method GET -Uri "$BaseUrl/agents?siteIds=$siteID&limit=500" -Headers $Headers
        $s1ComputerList = New-Object System.Collections.Generic.List[string]
        
        foreach ($entry in $getAgents.data) {
            $s1ComputerList.Add($entry.computerName) > $null
        }

        return $s1ComputerList
    }
    catch {
        Write-Error "Something went wrong when trying to retrieve agent list: $_"
        return @()
    }
}

function Get-RMMDevices {
    param (
        [System.Security.SecureString]$RMMApiSecretSecure
    )
    $limit = 500
    $BaseUrl = "https://<your-instance-name>/api/platform/v1" # Replace <your-instance-name> with your unique console URL.
    $RMMSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($RMMApiSecretSecure))
    $Body = @{
        "grant_type"    = "client_credentials"
        "client_id"     = "$RMMApiId"
        "client_secret" = "$RMMSecret"
        "scope"         = "platform.devices.read platform.companies.read platform.asset.read"
    }
    $JsonBody = $Body | ConvertTo-Json -Depth 3
    $rmmComputers = New-Object System.Collections.Generic.List[string]
    # Create Authorization Token
    try {
        $response = Invoke-RestMethod -Method POST -Uri "$BaseUrl" -Headers $Headers -Body $JsonBody
        $accessToken = $response.access_token
    }
    catch {
        Write-Error "Failed to retrieve access token: $_"
    }
    $Headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type"  = "application/json"
    }
    try {
        ## Checking the first page
        $getClientResponse = Invoke-RestMethod -Method GET -Uri "$BaseUrl/company/companies?limit=$limit" -Headers $Headers
        $clientInfo = $getClientResponse | Where-Object { $_.friendlyName -ilike "*$clientName*" }
        $nextLink = "Placeholder"
        $getLinkResponse = Invoke-WebRequest -Method GET -Uri "$BaseUrl/company/companies?limit=$limit" -Headers $Headers

        ## Pagination loop
        while (-not $clientInfo -and $nextLink) {
            $nextLink = $getLinkResponse.RelationLink.Values
            $getClientResponse = Invoke-RestMethod -Method GET -Uri "$nextLink" -Headers $Headers
            $clientInfo = $getClientResponse | Where-Object { $_.friendlyName -ilike "*$clientName*" }
            $getLinkResponse = Invoke-WebRequest -Method GET -Uri "$nextLink" -Headers $Headers
        }

        # Retrieve device IDs
        $getDevices = Invoke-RestMethod -Method GET -Uri "$BaseUrl/device/clients/$($clientInfo.id)/endpoints" -Headers $Headers
        $deviceList = $getDevices.endpoints

        # Retrieve device names and add to list
        foreach ($device in $deviceList) {
            $getEndpoint = Invoke-RestMethod -Method GET -Uri "$BaseUrl/device/endpoints/$($device.endpointID)" -Headers $Headers
            $null = $rmmComputers.Add($getEndpoint.system.systemName)
        }
        
        return $rmmComputers
    }
    catch {
        Write-Error "Something went wrong: $_"
        return $null
    }
}

function Get-DomainComputers {
    param (
        [string]$SearchBase = "",
        [int]$Days = 30
    )
    try {
        Import-Module ActiveDirectory -ErrorAction Stop

        $cutoff = (Get-Date).AddDays(-$Days)

        $computers = Get-ADComputer -Filter * -SearchBase $SearchBase -Properties Name, LastLogonDate |
        Where-Object { $_.LastLogonDate -gt $cutoff } |
        Select-Object -ExpandProperty Name

        return , $computers
    }
    catch {
        Write-Output "Failed to retrieve recently active computers: $_"
        return @()
    }
}

function Compare-ComputerLists {
    $domainComputers = $domainComputers | ForEach-Object { if ($_ -ne $null) { $_.ToUpper() } }
    $SentinelOneList = $SentinelOneList | ForEach-Object { if ($_ -ne $null) { $_.ToUpper() } }
    $rmmComputers = $rmmComputers    | ForEach-Object { if ($_ -ne $null) { $_.ToUpper() } }

    $missingFromDomain = $domainComputers | Where-Object { $_ -notin $rmmComputers }  # Domain but not in RMM
    $missingFromS1 = $rmmComputers        | Where-Object { $_ -notin $SentinelOneList }  # RMM but not in S1

    return @{
        MissingFromDomain = $missingFromDomain
        MissingFromS1     = $missingFromS1
    }
}

$SentinelOneList = Get-S1APIDevices -S1ApiTokenSecure $S1ApiToken
if (-not $SentinelOneList) {
    Write-Output "Sentinel One device list is empty."
}

$domainComputers = Get-DomainComputers
if ($domainComputers -contains "Failed") {
    Write-Output "Domain computer list is empty."
}

$rmmComputers = Get-RMMDevices -RMMApiSecretSecure $RMMApiSecret
if (-not $rmmComputers) {
    Write-Output "CW RMM computer list is empty."
}

# Comparing the lists above
$result = Compare-ComputerLists -rmmComputers $rmmComputers -domainComputers $domainComputers -s1Computers $SentinelOneList
$result.MissingFromDomain | Where-Object { $_ } | ForEach-Object {
    [PSCustomObject]@{
        ComputerName = $_.ToString().Trim()
        MissingFrom  = "Domain"
    }
} | Export-Csv "$workingdir\MissingInDomain.csv" -NoTypeInformation -Force
$result.MissingFromS1 | Where-Object { $_ } | ForEach-Object {
    [PSCustomObject]@{
        ComputerName = $_.ToString().Trim()
        MissingFrom  = "SentinelOne"
    }
} | Export-Csv "$workingdir\MissingInS1.csv" -NoTypeInformation -Force

Write-Output "Script completed, please see csv files in C:\Working."