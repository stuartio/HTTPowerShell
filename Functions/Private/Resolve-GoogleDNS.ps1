<#
.SYNOPSIS
Resolve DNS request from Google's DoH
.DESCRIPTION
Make a simple DNS request to Google's DoH server, with optional type
.NOTES
Author: S Macleod
Date: 29/10/25
.PARAMETER Name
Hostname to resolve
.PARAMETER Type
DNS Type to use
#>
function Resolve-GoogleDNS {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string]
        $Name,

        [Parameter()]
        [string]
        $Type
    )

    Process {
        $Query = "name=$Name"
        if ($Type) {
            $Query += "&type=$Type"
        }
        $RequestParams = @{
            Method = 'GET'
            Uri    = "https://dns.google/resolve?$Query"
        }
        try {
            $Result = Invoke-RestMethod @RequestParams
        }
        catch {
            throw "Resolve-GoogleDNS: DNS lookup failed: $_"
        }

        if ($null -eq $Result.Answer) {
            throw "Resolve-GoogleDNS: Hostname $Hostname does not resolve in DNS."
        }

        return $Result.answer
    }
}