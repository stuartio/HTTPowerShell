<#
.SYNOPSIS
Resolve hostname to Akamai Staging Network
.DESCRIPTION
Resolves hostname's CNAME chain to determine local Akamai staging IP
.NOTES
Author: S MAcleod
Date: 29/10/25
.PARAMETER Hostname
Hostname to resolve
#>
function Get-AkamaiStagingIP {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string]
        $Hostname
    )

    # ---- Get DNS
    $DNS = Resolve-GoogleDNS -Name $Hostname

    # ---- Determine low-level map
    $LLMap = ($DNS | Where-Object { $_.name.contains('.akamai.net') -or $_.name.contains('.akamaiedge.net') }).Name
    if ($LLMap.count -gt 1) { $LLMap = $LLMap[0] }
    Write-Debug "Get-AkamaiStagingIP: LLMap = $LLMap"

    if ($null -eq $LLMap) {
        throw "Unable to infer low-level map from response: $($DNS)"
    }

    # ---- Determine Staging
    $StagingLLMap = $LLMap.Replace('akamaiedge.net', 'akamaiedge-staging.net')
    $StagingLLMap = $StagingLLMap.Replace('akamai.net', 'akamai-staging.net')
    Write-Debug "Get-AkamaiStagingIP: Staging LLMap = $StagingLLMap"

    $StagingDNS = Resolve-GoogleDNS -Name $StagingLLMap
    $StagingIP = $StagingDNS[-1].data
    Write-Debug "Get-AkamaiStagingIP: StagingIP = $StagingIP"
    return $StagingIP
}