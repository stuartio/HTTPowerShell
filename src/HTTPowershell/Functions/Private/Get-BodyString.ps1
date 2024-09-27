function Get-BodyString {
    Param(
        [Parameter(Mandatory)]
        $Body
    )

    # Convert PSCustomObjects or Hashtables
    if ($Body -is 'PSCustomObject' -or $Body -is 'hashtable') {
        try {
            $BodyString = ConvertTo-Json -InputObject $Body -Depth 100
        }
        catch {
            Write-Error "Could not convert object to json"
            Write-Error $_
            return
        }
    }
    # Fall back to string
    else {
        $BodyString = $Body
    }
    return $BodyString
}