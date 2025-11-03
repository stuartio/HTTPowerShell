function ConvertTo-UTF8 {
    Param(
        [Parameter(Mandatory)]
        [string]
        $InputObject
    )

    $InputBytes = [System.Text.Encoding]::UTF8.GetBytes($InputObject)
    $OutputString = [System.Text.Encoding]::UTF8.GetString($InputBytes)
    return $OutputString
}