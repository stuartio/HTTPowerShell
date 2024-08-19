function Get-BodyString {
    Param(
        [Parameter(Mandatory)]
        $Body
    )

    if ($Body -is 'PSCustomObject' -or $Body -is 'Object' -or $Body -is 'hashtable') {
        try {
            $BodyString = ConvertTo-Json -InputObject $Body -Depth 100
        }
        catch {
            Write-Error "Could not convert object to json"
            Write-Error $_
            return
        }
    }
    else {
        $BodyString = $Body
    }
    return $BodyString
}