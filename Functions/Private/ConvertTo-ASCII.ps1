function ConvertTo-ASCII {
    Param(
        [Parameter(Mandatory)]
        [string]
        $InputObject
    )

    $InputBytes = [System.Text.Encoding]::ASCII.GetBytes($InputObject)
    $OutputString = [System.Text.Encoding]::ASCII.GetString($InputBytes)
    return $OutputString
}