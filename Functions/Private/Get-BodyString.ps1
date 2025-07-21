function Get-BodyString {
    Param(
        [Parameter(Mandatory)]
        $Body
    )

    # Convert PSCustomObjects or Hashtables
    if ($Body -is [PSCustomObject] -or $Body -is [Hashtable]) {
        try {
            $BodyString = ConvertTo-Json -InputObject $Body -Depth 100
        }
        catch {
            Write-Error "Could not convert object to json"
            Write-Error $_
            return
        }
    }
    # Convert XML
    elseif ($Body -is [System.Xml.XmlDocument]) {
        $BodyString = $Body.OuterXml
    }
    # Fall back to string
    else {
        $BodyString = $Body
    }
    return $BodyString
}