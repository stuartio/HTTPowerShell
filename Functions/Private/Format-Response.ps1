function Format-Response {
    Param(
        [Parameter(Mandatory)]
        $RawResponse
    )

    # ---- Handle byte[] response type
    if ($RawResponse -is 'byte[]') {
        $RawResponse = [System.Text.Encoding]::UTF8.GetString($RawResponse)
    }

    $Headers = New-Object -TypeName System.Collections.Generic.List[object]
    $StatusPattern = 'HTTP\/[0-9\.]+ (([0-9]+).*)'

    # ---- Split Headers and Body
    $ResponseComponents = $RawResponse -split "`r?`n`r?`n", 2
    $RawHeaders = $ResponseComponents[0].Trim()
    $Body = $ResponseComponents[1].Trim()
    $HeaderLines = $RawHeaders -split "`r`n" | Where-Object { $_ -ne '' }

    # ---- Parse header lines
    foreach ($Line in $HeaderLines) {
        if ($Line -Match $StatusPattern) {
            $StatusCode = [int] $Matches[2]
            $Status = $Line
        }
        else {
            $HeaderName = ($Line -split ':')[0].Trim()
            $HeaderValue = ($Line -split ':', 2)[1].Trim()
            $Headers.Add( [PSCustomObject] @{
                    Name  = $HeaderName
                    Value = $HeaderValue
                })
        }
    }

    # ---- Sort Headers
    $Headers = $Headers | Sort-Object -Property Name, Value

    # ---- Determine Content-Type
    $ContentType = $Headers |
    Where-Object { $_.name.ToLower() -eq 'content-type' } |
    Select-Object -First 1 |
    Select-Object -ExpandProperty value
    
    # ---- Construct output object
    $FormattedResponse = [PSCustomObject] @{
        StatusCode  = $StatusCode
        Status      = $Status
        Headers     = $Headers
        ContentType = $ContentType
        Body        = $Body
    }

    # ---- Handle multi-part response
    if ($ContentType -like 'multipart/form-data*') {
        $BoundaryMatch = $ContentType | Select-String -Pattern 'boundary=([^ ]*)'
        if ($BoundaryMatch) {
            $Boundary = $BoundaryMatch.Matches[0].Groups[1].Value
            $Parts = $Body -split "--$Boundary" | Where-Object { $_ -ne "" -and $_ -ne "--" }
            Write-Debug "Multi-Part: Found $($Parts.count) parts, separated by boundary $Boundary"

            if ($Parts.Count -gt 0) {
                $FormattedResponse | Add-Member -NotePropertyName Parts -NotePropertyValue (New-Object -TypeName System.Collections.Generic.List[object])
                foreach ($Part in $Parts) {
                    $FormattedPart = Format-Response -RawResponse $Part.Trim()
                    $FormattedResponse.Parts.Add($FormattedPart)
                }

                # Nullify main body, as it is contained in the parts
                $FormattedResponse.Body = $null
            }
        }
        else {
            Write-Warning "Failed to find boundary in Content-Type header: $ContentType"
        }
    }

    return $FormattedResponse
}