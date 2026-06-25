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
function Format-Response {
    Param(
        [Parameter(Mandatory)]
        $RawResponse,

        [Parameter()]
        [string[]]
        $DisplayHeaders
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

            if ($DisplayHeaders.Count -gt 0 -and $HeaderName -notin $DisplayHeaders) {
                Write-Debug "Skipping header: $HeaderName"
                continue
            }
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
function Get-AkamaiAuthHeader {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [PSCustomObject]
        $Credentials,

        [Parameter(Mandatory)]
        [string] 
        $Method,
        
        [Parameter(Mandatory)]
        [string]
        $ExpandedPath,

        [Parameter()]
        [string]
        $Body,
        
        [Parameter()]
        [string] 
        $InputFile,

        [Parameter()]
        [string] 
        $MaxBody = 131072
    )

    # Sanitize Method param
    $Method = $Method.ToUpper()

    # Timestamp for request signing
    $TimeStamp = [DateTime]::UtcNow.ToString("yyyyMMddTHH:mm:sszz00")

    # GUID for request signing
    $Nonce = [GUID]::NewGuid()

    # Build data string for signature generation
    $SignatureData = $Method + "`thttps`t"
    $SignatureData += $Credentials.Host + "`t" + $ExpandedPath

    #Sanitize body to remove NO-BREAK SPACE Unicode character, which breaks PAPI
    $Body = $Body -replace "[\u00a0]", ""

    # Add body to signature. Truncate if body is greater than max-body (Akamai default is 131072). PUT Method does not require adding to signature.
    if ($Method -eq "POST") {
        if ($Body) {
            $Body_SHA256 = [System.Security.Cryptography.SHA256]::Create()
            if ($Body.Length -gt $MaxBody) {
                $Body_Hash = [System.Convert]::ToBase64String($Body_SHA256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Body.Substring(0, $MaxBody))))
            }
            else {
                $Body_Hash = [System.Convert]::ToBase64String($Body_SHA256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Body)))
            }

            $SignatureData += "`t`t" + $Body_Hash + "`t"
        }
        elseif ($InputFile) {
            $Body_SHA256 = [System.Security.Cryptography.SHA256]::Create()
            if ($PSVersionTable.PSVersion.Major -lt 6) {
                $Bytes = Get-Content $InputFile -Encoding Byte
            }
            else {
                $Bytes = Get-Content $InputFile -AsByteStream
            }

            if ($Bytes.Length -gt $MaxBody) {
                $Body_Hash = [System.Convert]::ToBase64String($Body_SHA256.ComputeHash($Bytes[0..($MaxBody - 1)]))
            }
            else {
                $Body_Hash = [System.Convert]::ToBase64String($Body_SHA256.ComputeHash($Bytes))
            }

            $SignatureData += "`t`t" + $Body_Hash + "`t"
            Write-Debug "Signature generated from input file $InputFile"
        }
        else {
            $SignatureData += "`t`t`t"
        }
    }
    else {
        $SignatureData += "`t`t`t"
    }

    $SignatureData += "EG1-HMAC-SHA256 "
    $SignatureData += "client_token=" + $Credentials.client_token + ";"
    $SignatureData += "access_token=" + $Credentials.access_token + ";"
    $SignatureData += "timestamp=" + $TimeStamp + ";"
    $SignatureData += "nonce=" + $Nonce + ";"

    Write-Debug "SignatureData = $SignatureData"

    # Generate SigningKey
    $SigningKey = Get-EncryptedMessage -secret $Credentials.client_secret -message $TimeStamp

    # Generate Auth Signature
    $Signature = Get-EncryptedMessage -secret $SigningKey -message $SignatureData

    # Create AuthHeader
    $AuthorizationHeader = "EG1-HMAC-SHA256 "
    $AuthorizationHeader += "client_token=" + $Credentials.client_token + ";"
    $AuthorizationHeader += "access_token=" + $Credentials.access_token + ";"
    $AuthorizationHeader += "timestamp=" + $TimeStamp + ";"
    $AuthorizationHeader += "nonce=" + $Nonce + ";"
    $AuthorizationHeader += "signature=" + $Signature

    return $AuthorizationHeader
}

# SIG # Begin signature block
# MIIp2AYJKoZIhvcNAQcCoIIpyTCCKcUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBM44lgpxyN81z6
# PVWI9Jux118kcUSTj/RbPJ4ckPjLTaCCDo4wggawMIIEmKADAgECAhAIrUCyYNKc
# TJ9ezam9k67ZMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yMTA0MjkwMDAwMDBaFw0z
# NjA0MjgyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcg
# UlNBNDA5NiBTSEEzODQgMjAyMSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQDVtC9C0CiteLdd1TlZG7GIQvUzjOs9gZdwxbvEhSYwn6SOaNhc9es0
# JAfhS0/TeEP0F9ce2vnS1WcaUk8OoVf8iJnBkcyBAz5NcCRks43iCH00fUyAVxJr
# Q5qZ8sU7H/Lvy0daE6ZMswEgJfMQ04uy+wjwiuCdCcBlp/qYgEk1hz1RGeiQIXhF
# LqGfLOEYwhrMxe6TSXBCMo/7xuoc82VokaJNTIIRSFJo3hC9FFdd6BgTZcV/sk+F
# LEikVoQ11vkunKoAFdE3/hoGlMJ8yOobMubKwvSnowMOdKWvObarYBLj6Na59zHh
# 3K3kGKDYwSNHR7OhD26jq22YBoMbt2pnLdK9RBqSEIGPsDsJ18ebMlrC/2pgVItJ
# wZPt4bRc4G/rJvmM1bL5OBDm6s6R9b7T+2+TYTRcvJNFKIM2KmYoX7BzzosmJQay
# g9Rc9hUZTO1i4F4z8ujo7AqnsAMrkbI2eb73rQgedaZlzLvjSFDzd5Ea/ttQokbI
# YViY9XwCFjyDKK05huzUtw1T0PhH5nUwjewwk3YUpltLXXRhTT8SkXbev1jLchAp
# QfDVxW0mdmgRQRNYmtwmKwH0iU1Z23jPgUo+QEdfyYFQc4UQIyFZYIpkVMHMIRro
# OBl8ZhzNeDhFMJlP/2NPTLuqDQhTQXxYPUez+rbsjDIJAsxsPAxWEQIDAQABo4IB
# WTCCAVUwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUaDfg67Y7+F8Rhvv+
# YXsIiGX0TkIwHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0P
# AQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGCCsGAQUFBwEBBGswaTAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAC
# hjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9v
# dEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAcBgNVHSAEFTATMAcGBWeBDAED
# MAgGBmeBDAEEATANBgkqhkiG9w0BAQwFAAOCAgEAOiNEPY0Idu6PvDqZ01bgAhql
# +Eg08yy25nRm95RysQDKr2wwJxMSnpBEn0v9nqN8JtU3vDpdSG2V1T9J9Ce7FoFF
# UP2cvbaF4HZ+N3HLIvdaqpDP9ZNq4+sg0dVQeYiaiorBtr2hSBh+3NiAGhEZGM1h
# mYFW9snjdufE5BtfQ/g+lP92OT2e1JnPSt0o618moZVYSNUa/tcnP/2Q0XaG3Ryw
# YFzzDaju4ImhvTnhOE7abrs2nfvlIVNaw8rpavGiPttDuDPITzgUkpn13c5Ubdld
# AhQfQDN8A+KVssIhdXNSy0bYxDQcoqVLjc1vdjcshT8azibpGL6QB7BDf5WIIIJw
# 8MzK7/0pNVwfiThV9zeKiwmhywvpMRr/LhlcOXHhvpynCgbWJme3kuZOX956rEnP
# LqR0kq3bPKSchh/jwVYbKyP/j7XqiHtwa+aguv06P0WmxOgWkVKLQcBIhEuWTatE
# QOON8BUozu3xGFYHKi8QxAwIZDwzj64ojDzLj4gLDb879M4ee47vtevLt/B3E+bn
# KD+sEq6lLyJsQfmCXBVmzGwOysWGw/YmMwwHS6DTBwJqakAwSEs0qFEgu60bhQji
# WQ1tygVQK+pKHJ6l/aCnHwZ05/LWUpD9r4VIIflXO7ScA+2GRfS0YW6/aOImYIbq
# yK+p/pQd52MbOoZWeE4wggfWMIIFvqADAgECAhAJS8amgSAG6MIweRq3uiU3MA0G
# CSqGSIb3DQEBCwUAMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcg
# UlNBNDA5NiBTSEEzODQgMjAyMSBDQTEwHhcNMjUwNzAxMDAwMDAwWhcNMjYwMzA3
# MjM1OTU5WjCB3jETMBEGCysGAQQBgjc8AgEDEwJVUzEZMBcGCysGAQQBgjc8AgEC
# EwhEZWxhd2FyZTEdMBsGA1UEDwwUUHJpdmF0ZSBPcmdhbml6YXRpb24xEDAOBgNV
# BAUTBzI5MzM2MzcxCzAJBgNVBAYTAlVTMRYwFAYDVQQIEw1NYXNzYWNodXNldHRz
# MRIwEAYDVQQHEwlDYW1icmlkZ2UxIDAeBgNVBAoTF0FrYW1haSBUZWNobm9sb2dp
# ZXMgSW5jMSAwHgYDVQQDExdBa2FtYWkgVGVjaG5vbG9naWVzIEluYzCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBAMf1sSwHg7wzLGx81ZgJvrYMiCwYtKGv
# KNsDCkQsgYkqnuJYfiiRQ6kuk9RRUyqPLa9lLXa6xu6nBI8M6OzG9gxKNg7563G9
# 2P+lC1Gs6V8/uv5ZjzKwbKx3i40b4lHn+VeMNyooPZkzAjG9H8gNrCyCrk8FL7pL
# 1eOOPU1Hi3UWX9QHfBbI8HABRgyUPz7sNLDq0rRgcGIwvyIh5pqAoyBJE/HDXMCX
# ktktW+OMIIXXpSm9pcCVLT90etajQxCtH6LBV+CFDK/cxFeuDIyWdCR8DMC/oCdz
# ZoHbT3taOfN+lyMHUPWC8t7MkPg4OMqNG6nsF9yHDOAvL5h7PZe+npK/X4MYYsr1
# 7XFiak5H6hwiycQ8cVdPp+d0IeaQEnSqv5rI7IHc+V46sYmcmm/z5kvH9XWWD2VN
# Aj2Sdald4A9aipa143yG7yvyhmm/TCPco1QboXUuaZh6vpfH6u7mDFiQmOc15hw5
# Bc63ktDaGqHqujU2Fy9CGReZznEqrLv7jXNRuNyRnfc5oF2h8x8s2g0NaB3e3JVD
# l4utM2cYNe//akXajWRWWiEG21d2881vtRqyw/eE5fFDHJEdD633EBaLlkrn3K3x
# RoIhgsaEFUum9N43y1Cv3QVROED9jfTi5xTZnzSC36/uThhlJE+CFkEJeWGIrANx
# x3T+6/gEnQFZAgMBAAGjggICMIIB/jAfBgNVHSMEGDAWgBRoN+Drtjv4XxGG+/5h
# ewiIZfROQjAdBgNVHQ4EFgQUU+SbrrGchS0n0MB/su/rrjrMnMQwPQYDVR0gBDYw
# NDAyBgVngQwBAzApMCcGCCsGAQUFBwIBFhtodHRwOi8vd3d3LmRpZ2ljZXJ0LmNv
# bS9DUFMwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMIG1BgNV
# HR8Ega0wgaowU6BRoE+GTWh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dFRydXN0ZWRHNENvZGVTaWduaW5nUlNBNDA5NlNIQTM4NDIwMjFDQTEuY3JsMFOg
# UaBPhk1odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRD
# b2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNybDCBlAYIKwYBBQUHAQEE
# gYcwgYQwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBcBggr
# BgEFBQcwAoZQaHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1
# c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAyMUNBMS5jcnQwCQYDVR0T
# BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAVV2MjlQ7ejh5cR4thBQn3dxFI8z6OSFP
# ZURget+GnxVXGUlX2Qe4aNDHTV6GXqb7+JFTuT68WnAe6aWifWr+WmpoNJ7uQxJH
# T5t8OW+nK+eXcZLxF3weAQbxwaImGcEC/LKUwYnGttEM6ZsaqIg7H96w4/egNN/V
# i3CrIn4ASbganOwnHRW02DIw0lE6KLWcxDdLx07nLJxrjyAfxQqV2mrnPC9kAIJe
# U98TlkTaAzro8OWjiPxdQQ0AVd17hGLsKsjA8nz8HlCB9RmtvQ1LeRtVpHM/A6jX
# lP1Cl1mi6HRfAbck1ymomvNwbhLqCHsdoNJUFjZuYRaGHdtLAt+NJkXr5E9kOwoJ
# Isiq1n+D60HX4jOZ8crR0RsG2cbz/UD917kjWWRBoY5r4OLnVwCpOpjcFDlun2Bq
# usQg+UNWp2Tr6K2MhDePbHTQ2NEbnM89LKLtYHjDoh/zIRGlFqBNwEdCXG6HiThj
# fiAm40DhwxwJN7KsN/BJbPlXsNUL0I9YWtxnluFkkwxzWuee5hkweO71qCFJaJHx
# fd2/AakHLAgHa7EoOBYlqnjgp+MIIu9Stoi8EhdjeZOCE2JmH/dOstP6TLF2HlZy
# pvVaxOMZ0L1syN5z7pebN9dJ1qEsSdPQgxqRijFvbXILCSPrkDl9GO69AEh2HiMe
# i8g8MkCqzXMxghqgMIIanAIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5E
# aWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2Rl
# IFNpZ25pbmcgUlNBNDA5NiBTSEEzODQgMjAyMSBDQTECEAlLxqaBIAbowjB5Gre6
# JTcwDQYJYIZIAWUDBAIBBQCgfDAQBgorBgEEAYI3AgEMMQIwADAZBgkqhkiG9w0B
# CQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAv
# BgkqhkiG9w0BCQQxIgQgEiPiH72IuzflsiUWmn++FK3C5R4Qbcy+ukz7D5utTvAw
# DQYJKoZIhvcNAQEBBQAEggIAO4m6QG4RI90sLVsL8JL9LWbZtNbo8g3MaNthjF0u
# 7LOcgDVxPW6XTzUsrTAJ7b7DfaDObfBcKWtfcjYURON8rUnfVhJzgWPoxDZCmKIN
# 8xvMCazxwFPyLOzBsZO4DzmuMul3Uoxl059+md0KorG1JmUJmOlQ+vp83HhIlgMY
# uoBIrLq1RFhO4kw8rf8IAlwHmR3iirIc5OSqihS1Jwz7UtiLol4vIZmG6bQW960D
# F+HHjFZS54KrkEvE5pLFRbRDOMFvvjCEQ13fKP+SgduNhIY7ls53cvOrnf+Z2A+L
# +pfyfajd8NywRcGEj0R1D3aQjIeL5Xt8+SzExavttC9dNjTqaz47DAsnYFXAhWjD
# Kiw5KdtmGzHQdnEQnY4vcUb30D3DBDxlBRbCWYEL8HZGKWhgc0HDOTmM26gb7YuT
# yzqq90gedXV1p3OXma9BbPf0bq1QQ7s8GeBBnQG1ONR9t6mfDnRpnQrw5Xn9X2zT
# S6uO9wVq7zqQme+XxPxdY8reKlUj51z1xF2s8rimadKBM3ZDSVoi9d7zTFQEoIJW
# r6uVY/GDo+vnYArFPtz64da6abeIhPfB/0gDPFyuHa7K3Um3yuDYirCtvuMaYW97
# vu1VdXb7ezf9dUXgXM7RYJ1qYREEdlSjSKQKGXcYkopuy+4H858p4DIeau3icZx6
# TMChghd2MIIXcgYKKwYBBAGCNwMDATGCF2IwghdeBgkqhkiG9w0BBwKgghdPMIIX
# SwIBAzEPMA0GCWCGSAFlAwQCAQUAMHcGCyqGSIb3DQEJEAEEoGgEZjBkAgEBBglg
# hkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQg3hHxpwMphXWhsgv2/ku9HrPvKVkD
# Hv1kLWR8Srg1j1YCEDFB4rZXRa/nszdyPS6iVGcYDzIwMjUwODA1MTg0MTI5WqCC
# EzowggbtMIIE1aADAgECAhAKgO8YS43xBYLRxHanlXRoMA0GCSqGSIb3DQEBCwUA
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEy
# NTYgMjAyNSBDQTEwHhcNMjUwNjA0MDAwMDAwWhcNMzYwOTAzMjM1OTU5WjBjMQsw
# CQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRp
# Z2lDZXJ0IFNIQTI1NiBSU0E0MDk2IFRpbWVzdGFtcCBSZXNwb25kZXIgMjAyNSAx
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA0EasLRLGntDqrmBWsytX
# um9R/4ZwCgHfyjfMGUIwYzKomd8U1nH7C8Dr0cVMF3BsfAFI54um8+dnxk36+jx0
# Tb+k+87H9WPxNyFPJIDZHhAqlUPt281mHrBbZHqRK71Em3/hCGC5KyyneqiZ7syv
# FXJ9A72wzHpkBaMUNg7MOLxI6E9RaUueHTQKWXymOtRwJXcrcTTPPT2V1D/+cFll
# ESviH8YjoPFvZSjKs3SKO1QNUdFd2adw44wDcKgH+JRJE5Qg0NP3yiSyi5MxgU6c
# ehGHr7zou1znOM8odbkqoK+lJ25LCHBSai25CFyD23DZgPfDrJJJK77epTwMP6eK
# A0kWa3osAe8fcpK40uhktzUd/Yk0xUvhDU6lvJukx7jphx40DQt82yepyekl4i0r
# 8OEps/FNO4ahfvAk12hE5FVs9HVVWcO5J4dVmVzix4A77p3awLbr89A90/nWGjXM
# Gn7FQhmSlIUDy9Z2hSgctaepZTd0ILIUbWuhKuAeNIeWrzHKYueMJtItnj2Q+aTy
# LLKLM0MheP/9w6CtjuuVHJOVoIJ/DtpJRE7Ce7vMRHoRon4CWIvuiNN1Lk9Y+xZ6
# 6lazs2kKFSTnnkrT3pXWETTJkhd76CIDBbTRofOsNyEhzZtCGmnQigpFHti58CSm
# vEyJcAlDVcKacJ+A9/z7eacCAwEAAaOCAZUwggGRMAwGA1UdEwEB/wQCMAAwHQYD
# VR0OBBYEFOQ7/PIx7f391/ORcWMZUEPPYYzoMB8GA1UdIwQYMBaAFO9vU0rp5AZ8
# esrikFb2L9RJ7MtOMA4GA1UdDwEB/wQEAwIHgDAWBgNVHSUBAf8EDDAKBggrBgEF
# BQcDCDCBlQYIKwYBBQUHAQEEgYgwgYUwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3Nw
# LmRpZ2ljZXJ0LmNvbTBdBggrBgEFBQcwAoZRaHR0cDovL2NhY2VydHMuZGlnaWNl
# cnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5nUlNBNDA5NlNIQTI1
# NjIwMjVDQTEuY3J0MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly9jcmwzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEy
# NTYyMDI1Q0ExLmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEw
# DQYJKoZIhvcNAQELBQADggIBAGUqrfEcJwS5rmBB7NEIRJ5jQHIh+OT2Ik/bNYul
# CrVvhREafBYF0RkP2AGr181o2YWPoSHz9iZEN/FPsLSTwVQWo2H62yGBvg7ouCOD
# wrx6ULj6hYKqdT8wv2UV+Kbz/3ImZlJ7YXwBD9R0oU62PtgxOao872bOySCILdBg
# hQ/ZLcdC8cbUUO75ZSpbh1oipOhcUT8lD8QAGB9lctZTTOJM3pHfKBAEcxQFoHlt
# 2s9sXoxFizTeHihsQyfFg5fxUFEp7W42fNBVN4ueLaceRf9Cq9ec1v5iQMWTFQa0
# xNqItH3CPFTG7aEQJmmrJTV3Qhtfparz+BW60OiMEgV5GWoBy4RVPRwqxv7Mk0Sy
# 4QHs7v9y69NBqycz0BZwhB9WOfOu/CIJnzkQTwtSSpGGhLdjnQ4eBpjtP+XB3pQC
# tv4E5UCSDag6+iX8MmB10nfldPF9SVD7weCC3yXZi/uuhqdwkgVxuiMFzGVFwYbQ
# siGnoa9F5AaAyBjFBtXVLcKtapnMG3VH3EmAp/jsJ3FVF3+d1SVDTmjFjLbNFZUW
# MXuZyvgLfgyPehwJVxwC+UpX2MSey2ueIu9THFVkT+um1vshETaWyQo8gmBto/m3
# acaP9QsuLj3FNwFlTxq25+T4QwX9xa6ILs84ZPvmpovq90K8eWyG2N01c4IhSOxq
# t81nMIIGtDCCBJygAwIBAgIQDcesVwX/IZkuQEMiDDpJhjANBgkqhkiG9w0BAQsF
# ADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQL
# ExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJv
# b3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcNMzgwMTE0MjM1OTU5WjBpMQswCQYDVQQG
# EwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0
# IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0Ex
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAtHgx0wqYQXK+PEbAHKx1
# 26NGaHS0URedTa2NDZS1mZaDLFTtQ2oRjzUXMmxCqvkbsDpz4aH+qbxeLho8I6jY
# 3xL1IusLopuW2qftJYJaDNs1+JH7Z+QdSKWM06qchUP+AbdJgMQB3h2DZ0Mal5kY
# p77jYMVQXSZH++0trj6Ao+xh/AS7sQRuQL37QXbDhAktVJMQbzIBHYJBYgzWIjk8
# eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0Xm+nt5pnYJU3Gmq6bNMI1I7Gb5IBZK4i
# vbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQVESYOszFI2Wv82wnJRfN20VRS3hpLgIR4
# hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2qHxJ0ucS638ZxqU14lDnki7CcoKCz6eu
# m5A19WZQHkqUJfdkDjHkccpL6uoG8pbF0LJAQQZxst7VvwDDjAmSFTUms+wV/FbW
# Bqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgxCZSKi17yVp2NL+cnT6Toy+rN+nM8M7Ln
# LqCrO2JP3oW//1sfuZDKiDEb1AQ8es9Xr/u6bDTnYCTKIsDq1BtmXUqEG1NqzJKS
# 4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7OgWmnhFr4yUozZtqgPrHRVHhGNKlYzyjl
# roPxul+bgIspzOwbtmsgY1MCAwEAAaOCAV0wggFZMBIGA1UdEwEB/wQIMAYBAf8C
# AQAwHQYDVR0OBBYEFO9vU0rp5AZ8esrikFb2L9RJ7MtOMB8GA1UdIwQYMBaAFOzX
# 44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggr
# BgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3Nw
# LmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2VydHMuZGlnaWNl
# cnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYDVR0fBDwwOjA4oDag
# NIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RH
# NC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3
# DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEwvb4LyLU0pn/N0IfFiBowf0/Dm1wGc/Do
# 7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8G0iP5kvN2n7Jd2E4/iEIUBO41P5F448r
# SYJ59Ib61eoalhnd6ywFLerycvZTAz40y8S4F3/a+Z1jEMK/DMm/axFSgoR8n6c3
# nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCDA/JYsq7pGdogP8HRtrYfctSLANEBfHU1
# 6r3J05qX3kId+ZOczgj5kjatVB+NdADVZKON/gnZruMvNYY2o1f4MXRJDMdTSlOL
# h0HCn2cQLwQCqjFbqrXuvTPSegOOzr4EWj7PtspIHBldNE2K9i697cvaiIo2p61E
# d2p8xMJb82Yosn0z4y25xUbI7GIN/TpVfHIqQ6Ku/qjTY6hc3hsXMrS+U0yy+GWq
# AXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0c1ugMZyZZd/BdHLiRu7hAWE6bTEm4XYR
# kA6Tl4KSFLFk43esaUeqGkH/wyW4N7OigizwJWeukcyIPbAvjSabnf7+Pu0VrFgo
# iovRDiyx3zEdmcif/sYQsfch28bZeUz2rtY/9TCA6TD8dC3JE3rYkrhLULy7Dc90
# G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz0scmbKvFoW2jNrbM1pD2T7m3XDCCBY0w
# ggR1oAMCAQICEA6bGI750C3n79tQ4ghAGFowDQYJKoZIhvcNAQEMBQAwZTELMAkG
# A1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRp
# Z2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENB
# MB4XDTIyMDgwMTAwMDAwMFoXDTMxMTEwOTIzNTk1OVowYjELMAkGA1UEBhMCVVMx
# FTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNv
# bTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAv+aQc2jeu+RdSjwwIjBpM+zCpyUuySE98orY
# WcLhKac9WKt2ms2uexuEDcQwH/MbpDgW61bGl20dq7J58soR0uRf1gU8Ug9SH8ae
# FaV+vp+pVxZZVXKvaJNwwrK6dZlqczKU0RBEEC7fgvMHhOZ0O21x4i0MG+4g1ckg
# HWMpLc7sXk7Ik/ghYZs06wXGXuxbGrzryc/NrDRAX7F6Zu53yEioZldXn1RYjgwr
# t0+nMNlW7sp7XeOtyU9e5TXnMcvak17cjo+A2raRmECQecN4x7axxLVqGDgDEI3Y
# 1DekLgV9iPWCPhCRcKtVgkEy19sEcypukQF8IUzUvK4bA3VdeGbZOjFEmjNAvwjX
# WkmkwuapoGfdpCe8oU85tRFYF/ckXEaPZPfBaYh2mHY9WV1CdoeJl2l6SPDgohIb
# Zpp0yt5LHucOY67m1O+SkjqePdwA5EUlibaaRBkrfsCUtNJhbesz2cXfSwQAzH0c
# lcOP9yGyshG3u3/y1YxwLEFgqrFjGESVGnZifvaAsPvoZKYz0YkH4b235kOkGLim
# dwHhD5QMIR2yVCkliWzlDlJRR3S+Jqy2QXXeeqxfjT/JvNNBERJb5RBQ6zHFynIW
# IgnffEx1P2PsIV/EIFFrb7GrhotPwtZFX50g/KEexcCPorF+CiaZ9eRpL5gdLfXZ
# qbId5RsCAwEAAaOCATowggE2MA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFOzX
# 44LScV1kTN8uZz/nupiuHA9PMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3z
# bcgPMA4GA1UdDwEB/wQEAwIBhjB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGG
# GGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2Nh
# Y2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDBF
# BgNVHR8EPjA8MDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRBc3N1cmVkSURSb290Q0EuY3JsMBEGA1UdIAQKMAgwBgYEVR0gADANBgkqhkiG
# 9w0BAQwFAAOCAQEAcKC/Q1xV5zhfoKN0Gz22Ftf3v1cHvZqsoYcs7IVeqRq7IviH
# GmlUIu2kiHdtvRoU9BNKei8ttzjv9P+Aufih9/Jy3iS8UgPITtAq3votVs/59Pes
# MHqai7Je1M/RQ0SbQyHrlnKhSLSZy51PpwYDE3cnRNTnf+hZqPC/Lwum6fI0POz3
# A8eHqNJMQBk1RmppVLC4oVaO7KTVPeix3P0c2PR3WlxUjG/voVA9/HYJaISfb8rb
# II01YBwCA8sgsKxYoA5AY8WYIsGyWfVVa88nq2x2zm8jLfR+cWojayL/ErhULSd+
# 2DrZ8LaHlv1b0VysGMNNn3O3AamfV6peKOK5lDGCA3wwggN4AgEBMH0waTELMAkG
# A1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdp
# Q2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1
# IENBMQIQCoDvGEuN8QWC0cR2p5V0aDANBglghkgBZQMEAgEFAKCB0TAaBgkqhkiG
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwHAYJKoZIhvcNAQkFMQ8XDTI1MDgwNTE4NDEy
# OVowKwYLKoZIhvcNAQkQAgwxHDAaMBgwFgQU3WIwrIYKLTBr2jixaHlSMAf7QX4w
# LwYJKoZIhvcNAQkEMSIEIGP53Hhtnht1jkaf5pxb+M1U/C4ulY0pWhtlHZg6hED2
# MDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIEqgP6Is11yExVyTj4KOZ2ucrsqzP+Nt
# JpqjNPFGEQozMA0GCSqGSIb3DQEBAQUABIICACUODNKSqxrBMYK9oIJZzOJY7cD2
# f4fRMVnpKE6dUGHgTe4Mdw18pMt4RKLdVj4assBTKlaKp4ytwawD68xx5OYx8bXi
# 5XuzugwxYMKaQnCStf2CMhFLr435GMTHPx1zYPiNmMkP2Mafe7Q23GUCVePaKBff
# CAj/naEYi4ndYVghdEHTIxz3u+z/uh2wN7kOtdqloTM755CRT4U4KwLS7oFyI0k0
# Cyj8qxCLdHGPCRNkLndlwmeIt9mBFkcHHoBPEtLYDEmZtb9/jq5p1YUsdEfmiJfN
# ugqGGpvDWgOKF8xQwJslVFk0xu4koAdlzoBWXJwaoi+K/vNmtSTGiC9+RoKoewe4
# LSmst3YITilBI0grne8aNFyLxo7Mh6nTPtHht/lDAbSLF90lO6uMzCYi2FEnlL/y
# aaxwsZxNwiZWOKpZUmDR9txsQ5YvfkK5bVuj4iUmMOCY+iPq0TdO6yGYDjYv2kFY
# uDpQ4AyP03Y6wt8eM9nf9ih1KKJZH9gdU1P2kTkk1CtE1VyLgMyTaQjwvj2syNU4
# YuFqHMu3idaAXKv9mfraE6GmHQWme9LyK30LvQ3WqbzPmN/F/vNzJ9yV6792O2AD
# NqJNFvtWuibzyZJ42nNmX7QiO3mF3eJLC3nDCFUfZUbHePZtJcXT5+t/a9uZpre+
# HeWn0aTHjVotGS3z
# SIG # End signature block

function Get-AkamaiCredentials {
    [CmdletBinding()]
    Param(
        [Parameter()]
        [string]
        $EdgeRCFile,

        [Parameter()]
        [string]
        $Section,

        [Parameter()]
        [string]
        $AccountSwitchKey
    )

    ## Assign defaults if values not provided
    if ($EdgeRCFile -eq '') {
        $EdgeRCFile = '~/.edgerc'
    }
    else {
        ## If EdgeRCFile is provided we use that, regardless of other auth types being available
        $Mode = 'edgerc'
    }
    if ($Section -eq '') {
        $Section = 'default'
    }

    #----------------------------------------------------------------------------------------------
    #                              1. Check for existing session
    #----------------------------------------------------------------------------------------------

    if ($Mode -ne 'edgerc') {
        if ($null -ne $Script:AkamaiSession -and $null -ne $Script:AkamaiSession.Auth.$Section) {
            #Use the script session auth instead of a file
            $Auth = $Script:AkamaiSession.Auth.$Section
            Write-Debug "Obtained credentials from existing session in section '$Section'"
            return $Auth
        }
    }   
    

    #----------------------------------------------------------------------------------------------
    #                             2. Set up auth object
    #----------------------------------------------------------------------------------------------

    ## Instantiate auth object
    $AuthElements = @(
        'host',
        'client_token',
        'access_token',
        'client_secret',
        'account_key'
    )

    $Auth = New-Object -TypeName PSCustomObject
    $AuthElements | ForEach-Object {
        $Auth | Add-Member -MemberType NoteProperty -Name $_ -Value $null
    }

    #----------------------------------------------------------------------------------------------
    #                              3. Check for environment variables
    #----------------------------------------------------------------------------------------------
    
    ## 'default' section is implicit. Otherwise env variable starts with section prefix
    if ($Mode -ne 'edgerc') {
        if ($Section -eq 'default') {
            $EnvPrefix = 'AKAMAI_'
        }
        else {
            $EnvPrefix = "AKAMAI_$Section`_"
        }
    
        $AuthElements | ForEach-Object {
            $UpperEnv = "$EnvPrefix$_".ToUpper()
            if (Test-Path Env:\$UpperEnv) {
                $Auth.$_ = (Get-Item -Path Env:\$UpperEnv).Value
            }
        }

        ## Explicit ASK wins over env variable
        if ($AccountSwitchKey) {
            $Auth.account_key = $AccountSwitchKey
        }

        ## Remove ASK if value is "none"
        if ($AccountSwitchKey -eq "none") {
            $Auth.account_key = $null
        }

        ## Check essential elements and return
        if ($null -ne $Auth.host -and $null -ne $Auth.client_token -and $null -ne $Auth.access_token -and $null -ne $Auth.client_secret) {
            ## Env creds valid
            Write-Debug "Obtained credentials from environment variables in section '$Section'"
            return $Auth
        }
    }

    #----------------------------------------------------------------------------------------------
    #                              4. Read from .edgerc file
    #----------------------------------------------------------------------------------------------

    # Get credentials from EdgeRC
    if (Test-Path $EdgeRCFile) {
        $EdgeRCContent = Get-Content $EdgeRCFile
        foreach ($line in $EdgeRCContent) {
            $SanitizedLine = $line.Replace(" ", "")

            ## Set SectionHeader variable if line is a header.
            if ($SanitizedLine.contains("[") -and $SanitizedLine.contains("]")) {
                $SectionHeader = $SanitizedLine.Substring($SanitizedLine.indexOf('[') + 1)
                $SectionHeader = $SectionHeader.SubString(0, $SectionHeader.IndexOf(']'))
            }

            ## Skip sections other than desired one
            if ($SectionHeader -ne $Section) { continue }

            if ($SanitizedLine.ToLower().StartsWith("client_token")) { $Auth.client_token = $SanitizedLine.SubString($SanitizedLine.IndexOf("=") + 1) }
            if ($SanitizedLine.ToLower().StartsWith("access_token")) { $Auth.access_token = $SanitizedLine.SubString($SanitizedLine.IndexOf("=") + 1) }
            if ($SanitizedLine.ToLower().StartsWith("host")) { $Auth.host = $SanitizedLine.SubString($SanitizedLine.IndexOf("=") + 1) }
            if ($SanitizedLine.ToLower().StartsWith("client_secret")) { $Auth.client_secret = $SanitizedLine.SubString($SanitizedLine.IndexOf("=") + 1) }
            if ($SanitizedLine.ToLower().StartsWith("account_key")) { $Auth.account_key = $SanitizedLine.SubString($SanitizedLine.IndexOf("=") + 1) }
        }

        ## Explicit ASK wins over edgerc file entry
        if ($AccountSwitchKey) {
            $Auth.account_key = $AccountSwitchKey
        }

        ## Remove ASK if value is "none"
        if ($AccountSwitchKey -eq "none") {
            $Auth.account_key = $null
        }

        ## Check essential elements and return
        if ($null -ne $Auth.host -and $null -ne $Auth.client_token -and $null -ne $Auth.access_token -and $null -ne $Auth.client_secret) {
            Write-Debug "Obtained credentials from edgerc file '$EdgeRCFile' in section '$Section'"
            return $Auth
        }
    }
    
    #----------------------------------------------------------------------------------------------
    #                                     5. Panic!
    #----------------------------------------------------------------------------------------------

    ## Under normal circumstances you should not get this far...    
    throw "Error: Credentials could not be loaded from either; session, environment variables or edgerc file '$EdgeRCFile'"

}


# SIG # Begin signature block
# MIIp2AYJKoZIhvcNAQcCoIIpyTCCKcUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD5voaUdIdV9CYh
# ZlUTgeN/xAin7i2mng+s25GiLO0FYqCCDo4wggawMIIEmKADAgECAhAIrUCyYNKc
# TJ9ezam9k67ZMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yMTA0MjkwMDAwMDBaFw0z
# NjA0MjgyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcg
# UlNBNDA5NiBTSEEzODQgMjAyMSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQDVtC9C0CiteLdd1TlZG7GIQvUzjOs9gZdwxbvEhSYwn6SOaNhc9es0
# JAfhS0/TeEP0F9ce2vnS1WcaUk8OoVf8iJnBkcyBAz5NcCRks43iCH00fUyAVxJr
# Q5qZ8sU7H/Lvy0daE6ZMswEgJfMQ04uy+wjwiuCdCcBlp/qYgEk1hz1RGeiQIXhF
# LqGfLOEYwhrMxe6TSXBCMo/7xuoc82VokaJNTIIRSFJo3hC9FFdd6BgTZcV/sk+F
# LEikVoQ11vkunKoAFdE3/hoGlMJ8yOobMubKwvSnowMOdKWvObarYBLj6Na59zHh
# 3K3kGKDYwSNHR7OhD26jq22YBoMbt2pnLdK9RBqSEIGPsDsJ18ebMlrC/2pgVItJ
# wZPt4bRc4G/rJvmM1bL5OBDm6s6R9b7T+2+TYTRcvJNFKIM2KmYoX7BzzosmJQay
# g9Rc9hUZTO1i4F4z8ujo7AqnsAMrkbI2eb73rQgedaZlzLvjSFDzd5Ea/ttQokbI
# YViY9XwCFjyDKK05huzUtw1T0PhH5nUwjewwk3YUpltLXXRhTT8SkXbev1jLchAp
# QfDVxW0mdmgRQRNYmtwmKwH0iU1Z23jPgUo+QEdfyYFQc4UQIyFZYIpkVMHMIRro
# OBl8ZhzNeDhFMJlP/2NPTLuqDQhTQXxYPUez+rbsjDIJAsxsPAxWEQIDAQABo4IB
# WTCCAVUwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUaDfg67Y7+F8Rhvv+
# YXsIiGX0TkIwHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0P
# AQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGCCsGAQUFBwEBBGswaTAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAC
# hjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9v
# dEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAcBgNVHSAEFTATMAcGBWeBDAED
# MAgGBmeBDAEEATANBgkqhkiG9w0BAQwFAAOCAgEAOiNEPY0Idu6PvDqZ01bgAhql
# +Eg08yy25nRm95RysQDKr2wwJxMSnpBEn0v9nqN8JtU3vDpdSG2V1T9J9Ce7FoFF
# UP2cvbaF4HZ+N3HLIvdaqpDP9ZNq4+sg0dVQeYiaiorBtr2hSBh+3NiAGhEZGM1h
# mYFW9snjdufE5BtfQ/g+lP92OT2e1JnPSt0o618moZVYSNUa/tcnP/2Q0XaG3Ryw
# YFzzDaju4ImhvTnhOE7abrs2nfvlIVNaw8rpavGiPttDuDPITzgUkpn13c5Ubdld
# AhQfQDN8A+KVssIhdXNSy0bYxDQcoqVLjc1vdjcshT8azibpGL6QB7BDf5WIIIJw
# 8MzK7/0pNVwfiThV9zeKiwmhywvpMRr/LhlcOXHhvpynCgbWJme3kuZOX956rEnP
# LqR0kq3bPKSchh/jwVYbKyP/j7XqiHtwa+aguv06P0WmxOgWkVKLQcBIhEuWTatE
# QOON8BUozu3xGFYHKi8QxAwIZDwzj64ojDzLj4gLDb879M4ee47vtevLt/B3E+bn
# KD+sEq6lLyJsQfmCXBVmzGwOysWGw/YmMwwHS6DTBwJqakAwSEs0qFEgu60bhQji
# WQ1tygVQK+pKHJ6l/aCnHwZ05/LWUpD9r4VIIflXO7ScA+2GRfS0YW6/aOImYIbq
# yK+p/pQd52MbOoZWeE4wggfWMIIFvqADAgECAhAJS8amgSAG6MIweRq3uiU3MA0G
# CSqGSIb3DQEBCwUAMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcg
# UlNBNDA5NiBTSEEzODQgMjAyMSBDQTEwHhcNMjUwNzAxMDAwMDAwWhcNMjYwMzA3
# MjM1OTU5WjCB3jETMBEGCysGAQQBgjc8AgEDEwJVUzEZMBcGCysGAQQBgjc8AgEC
# EwhEZWxhd2FyZTEdMBsGA1UEDwwUUHJpdmF0ZSBPcmdhbml6YXRpb24xEDAOBgNV
# BAUTBzI5MzM2MzcxCzAJBgNVBAYTAlVTMRYwFAYDVQQIEw1NYXNzYWNodXNldHRz
# MRIwEAYDVQQHEwlDYW1icmlkZ2UxIDAeBgNVBAoTF0FrYW1haSBUZWNobm9sb2dp
# ZXMgSW5jMSAwHgYDVQQDExdBa2FtYWkgVGVjaG5vbG9naWVzIEluYzCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBAMf1sSwHg7wzLGx81ZgJvrYMiCwYtKGv
# KNsDCkQsgYkqnuJYfiiRQ6kuk9RRUyqPLa9lLXa6xu6nBI8M6OzG9gxKNg7563G9
# 2P+lC1Gs6V8/uv5ZjzKwbKx3i40b4lHn+VeMNyooPZkzAjG9H8gNrCyCrk8FL7pL
# 1eOOPU1Hi3UWX9QHfBbI8HABRgyUPz7sNLDq0rRgcGIwvyIh5pqAoyBJE/HDXMCX
# ktktW+OMIIXXpSm9pcCVLT90etajQxCtH6LBV+CFDK/cxFeuDIyWdCR8DMC/oCdz
# ZoHbT3taOfN+lyMHUPWC8t7MkPg4OMqNG6nsF9yHDOAvL5h7PZe+npK/X4MYYsr1
# 7XFiak5H6hwiycQ8cVdPp+d0IeaQEnSqv5rI7IHc+V46sYmcmm/z5kvH9XWWD2VN
# Aj2Sdald4A9aipa143yG7yvyhmm/TCPco1QboXUuaZh6vpfH6u7mDFiQmOc15hw5
# Bc63ktDaGqHqujU2Fy9CGReZznEqrLv7jXNRuNyRnfc5oF2h8x8s2g0NaB3e3JVD
# l4utM2cYNe//akXajWRWWiEG21d2881vtRqyw/eE5fFDHJEdD633EBaLlkrn3K3x
# RoIhgsaEFUum9N43y1Cv3QVROED9jfTi5xTZnzSC36/uThhlJE+CFkEJeWGIrANx
# x3T+6/gEnQFZAgMBAAGjggICMIIB/jAfBgNVHSMEGDAWgBRoN+Drtjv4XxGG+/5h
# ewiIZfROQjAdBgNVHQ4EFgQUU+SbrrGchS0n0MB/su/rrjrMnMQwPQYDVR0gBDYw
# NDAyBgVngQwBAzApMCcGCCsGAQUFBwIBFhtodHRwOi8vd3d3LmRpZ2ljZXJ0LmNv
# bS9DUFMwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMIG1BgNV
# HR8Ega0wgaowU6BRoE+GTWh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dFRydXN0ZWRHNENvZGVTaWduaW5nUlNBNDA5NlNIQTM4NDIwMjFDQTEuY3JsMFOg
# UaBPhk1odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRD
# b2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNybDCBlAYIKwYBBQUHAQEE
# gYcwgYQwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBcBggr
# BgEFBQcwAoZQaHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1
# c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAyMUNBMS5jcnQwCQYDVR0T
# BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAVV2MjlQ7ejh5cR4thBQn3dxFI8z6OSFP
# ZURget+GnxVXGUlX2Qe4aNDHTV6GXqb7+JFTuT68WnAe6aWifWr+WmpoNJ7uQxJH
# T5t8OW+nK+eXcZLxF3weAQbxwaImGcEC/LKUwYnGttEM6ZsaqIg7H96w4/egNN/V
# i3CrIn4ASbganOwnHRW02DIw0lE6KLWcxDdLx07nLJxrjyAfxQqV2mrnPC9kAIJe
# U98TlkTaAzro8OWjiPxdQQ0AVd17hGLsKsjA8nz8HlCB9RmtvQ1LeRtVpHM/A6jX
# lP1Cl1mi6HRfAbck1ymomvNwbhLqCHsdoNJUFjZuYRaGHdtLAt+NJkXr5E9kOwoJ
# Isiq1n+D60HX4jOZ8crR0RsG2cbz/UD917kjWWRBoY5r4OLnVwCpOpjcFDlun2Bq
# usQg+UNWp2Tr6K2MhDePbHTQ2NEbnM89LKLtYHjDoh/zIRGlFqBNwEdCXG6HiThj
# fiAm40DhwxwJN7KsN/BJbPlXsNUL0I9YWtxnluFkkwxzWuee5hkweO71qCFJaJHx
# fd2/AakHLAgHa7EoOBYlqnjgp+MIIu9Stoi8EhdjeZOCE2JmH/dOstP6TLF2HlZy
# pvVaxOMZ0L1syN5z7pebN9dJ1qEsSdPQgxqRijFvbXILCSPrkDl9GO69AEh2HiMe
# i8g8MkCqzXMxghqgMIIanAIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5E
# aWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2Rl
# IFNpZ25pbmcgUlNBNDA5NiBTSEEzODQgMjAyMSBDQTECEAlLxqaBIAbowjB5Gre6
# JTcwDQYJYIZIAWUDBAIBBQCgfDAQBgorBgEEAYI3AgEMMQIwADAZBgkqhkiG9w0B
# CQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAv
# BgkqhkiG9w0BCQQxIgQg+6Uuf1ZMnpaynjsTE2vRCUPJ1ONXqd8QAZUZYj24+asw
# DQYJKoZIhvcNAQEBBQAEggIASFv/j1JjYO0osgoivemjFl95reV8/ShkV6YYxemT
# vupLa3d+8kTeukeQfuodZzfCQfXLky9CPszFsDe0qQWmIaokNwwYtntx23uGPd5g
# qthjBSUvm9PXT/qrXBEtzZ2uT6f3MtVDBl84hUs3AF2+TQhBCtKt1QV7TtPCEXG1
# YAXP09hkZROW7+4+bODTMjyRST13nxx6sIsu5JhujpcNSyCV586OQKud22MNFnJY
# crh1Vcc/ya/yAaRB0XzOxjhMgS16U3MMulMjNNiz3GG7PjH015nzGR++NgAjSXv0
# PCJiwj0RAErxQIiaMlVzuhBB5NQgpchf2Juj2ichVXsjoxsCHR5VChS6a9gehHNQ
# T42b4ceD5AUDsxsT0HWlsBieoxVwKdP7gG40xu+zdzY1KV6y8agO6WoU/W+r+4mJ
# GXCUE5hihg8rLuwei13r1xk58TSeOZL4dqvczswnhJmXmvjrlpzoPWcgZAPGblkC
# +ZIwpaHvJLkSg2IECiTaZ97P9x1uyFmJ9Lv3eg+xwRSYmTT9rnQ6PtJDYPfkOtIs
# MpTFTfAR5QUfC8I6hL4GVI69SAmp5yKmH1rMdC1RfJSvlsZSQIDbzWUKBmdvNgxY
# pQB2IYOzUB3nPy4+nN9BcwNPfNqLr0g+/dNoCu+/7KI9jBIs9siBjqOiVvkTvWOp
# 2zChghd2MIIXcgYKKwYBBAGCNwMDATGCF2IwghdeBgkqhkiG9w0BBwKgghdPMIIX
# SwIBAzEPMA0GCWCGSAFlAwQCAQUAMHcGCyqGSIb3DQEJEAEEoGgEZjBkAgEBBglg
# hkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQgsjcUJYAF2FxGQabfChMmjduYi8wX
# CSANIMQ34dQMo04CEGzLQwSbFsOyHgw56QAc9XQYDzIwMjUwODA1MTg0MDExWqCC
# EzowggbtMIIE1aADAgECAhAKgO8YS43xBYLRxHanlXRoMA0GCSqGSIb3DQEBCwUA
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEy
# NTYgMjAyNSBDQTEwHhcNMjUwNjA0MDAwMDAwWhcNMzYwOTAzMjM1OTU5WjBjMQsw
# CQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRp
# Z2lDZXJ0IFNIQTI1NiBSU0E0MDk2IFRpbWVzdGFtcCBSZXNwb25kZXIgMjAyNSAx
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA0EasLRLGntDqrmBWsytX
# um9R/4ZwCgHfyjfMGUIwYzKomd8U1nH7C8Dr0cVMF3BsfAFI54um8+dnxk36+jx0
# Tb+k+87H9WPxNyFPJIDZHhAqlUPt281mHrBbZHqRK71Em3/hCGC5KyyneqiZ7syv
# FXJ9A72wzHpkBaMUNg7MOLxI6E9RaUueHTQKWXymOtRwJXcrcTTPPT2V1D/+cFll
# ESviH8YjoPFvZSjKs3SKO1QNUdFd2adw44wDcKgH+JRJE5Qg0NP3yiSyi5MxgU6c
# ehGHr7zou1znOM8odbkqoK+lJ25LCHBSai25CFyD23DZgPfDrJJJK77epTwMP6eK
# A0kWa3osAe8fcpK40uhktzUd/Yk0xUvhDU6lvJukx7jphx40DQt82yepyekl4i0r
# 8OEps/FNO4ahfvAk12hE5FVs9HVVWcO5J4dVmVzix4A77p3awLbr89A90/nWGjXM
# Gn7FQhmSlIUDy9Z2hSgctaepZTd0ILIUbWuhKuAeNIeWrzHKYueMJtItnj2Q+aTy
# LLKLM0MheP/9w6CtjuuVHJOVoIJ/DtpJRE7Ce7vMRHoRon4CWIvuiNN1Lk9Y+xZ6
# 6lazs2kKFSTnnkrT3pXWETTJkhd76CIDBbTRofOsNyEhzZtCGmnQigpFHti58CSm
# vEyJcAlDVcKacJ+A9/z7eacCAwEAAaOCAZUwggGRMAwGA1UdEwEB/wQCMAAwHQYD
# VR0OBBYEFOQ7/PIx7f391/ORcWMZUEPPYYzoMB8GA1UdIwQYMBaAFO9vU0rp5AZ8
# esrikFb2L9RJ7MtOMA4GA1UdDwEB/wQEAwIHgDAWBgNVHSUBAf8EDDAKBggrBgEF
# BQcDCDCBlQYIKwYBBQUHAQEEgYgwgYUwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3Nw
# LmRpZ2ljZXJ0LmNvbTBdBggrBgEFBQcwAoZRaHR0cDovL2NhY2VydHMuZGlnaWNl
# cnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5nUlNBNDA5NlNIQTI1
# NjIwMjVDQTEuY3J0MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly9jcmwzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEy
# NTYyMDI1Q0ExLmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEw
# DQYJKoZIhvcNAQELBQADggIBAGUqrfEcJwS5rmBB7NEIRJ5jQHIh+OT2Ik/bNYul
# CrVvhREafBYF0RkP2AGr181o2YWPoSHz9iZEN/FPsLSTwVQWo2H62yGBvg7ouCOD
# wrx6ULj6hYKqdT8wv2UV+Kbz/3ImZlJ7YXwBD9R0oU62PtgxOao872bOySCILdBg
# hQ/ZLcdC8cbUUO75ZSpbh1oipOhcUT8lD8QAGB9lctZTTOJM3pHfKBAEcxQFoHlt
# 2s9sXoxFizTeHihsQyfFg5fxUFEp7W42fNBVN4ueLaceRf9Cq9ec1v5iQMWTFQa0
# xNqItH3CPFTG7aEQJmmrJTV3Qhtfparz+BW60OiMEgV5GWoBy4RVPRwqxv7Mk0Sy
# 4QHs7v9y69NBqycz0BZwhB9WOfOu/CIJnzkQTwtSSpGGhLdjnQ4eBpjtP+XB3pQC
# tv4E5UCSDag6+iX8MmB10nfldPF9SVD7weCC3yXZi/uuhqdwkgVxuiMFzGVFwYbQ
# siGnoa9F5AaAyBjFBtXVLcKtapnMG3VH3EmAp/jsJ3FVF3+d1SVDTmjFjLbNFZUW
# MXuZyvgLfgyPehwJVxwC+UpX2MSey2ueIu9THFVkT+um1vshETaWyQo8gmBto/m3
# acaP9QsuLj3FNwFlTxq25+T4QwX9xa6ILs84ZPvmpovq90K8eWyG2N01c4IhSOxq
# t81nMIIGtDCCBJygAwIBAgIQDcesVwX/IZkuQEMiDDpJhjANBgkqhkiG9w0BAQsF
# ADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQL
# ExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJv
# b3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcNMzgwMTE0MjM1OTU5WjBpMQswCQYDVQQG
# EwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0
# IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0Ex
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAtHgx0wqYQXK+PEbAHKx1
# 26NGaHS0URedTa2NDZS1mZaDLFTtQ2oRjzUXMmxCqvkbsDpz4aH+qbxeLho8I6jY
# 3xL1IusLopuW2qftJYJaDNs1+JH7Z+QdSKWM06qchUP+AbdJgMQB3h2DZ0Mal5kY
# p77jYMVQXSZH++0trj6Ao+xh/AS7sQRuQL37QXbDhAktVJMQbzIBHYJBYgzWIjk8
# eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0Xm+nt5pnYJU3Gmq6bNMI1I7Gb5IBZK4i
# vbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQVESYOszFI2Wv82wnJRfN20VRS3hpLgIR4
# hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2qHxJ0ucS638ZxqU14lDnki7CcoKCz6eu
# m5A19WZQHkqUJfdkDjHkccpL6uoG8pbF0LJAQQZxst7VvwDDjAmSFTUms+wV/FbW
# Bqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgxCZSKi17yVp2NL+cnT6Toy+rN+nM8M7Ln
# LqCrO2JP3oW//1sfuZDKiDEb1AQ8es9Xr/u6bDTnYCTKIsDq1BtmXUqEG1NqzJKS
# 4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7OgWmnhFr4yUozZtqgPrHRVHhGNKlYzyjl
# roPxul+bgIspzOwbtmsgY1MCAwEAAaOCAV0wggFZMBIGA1UdEwEB/wQIMAYBAf8C
# AQAwHQYDVR0OBBYEFO9vU0rp5AZ8esrikFb2L9RJ7MtOMB8GA1UdIwQYMBaAFOzX
# 44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggr
# BgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3Nw
# LmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2VydHMuZGlnaWNl
# cnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYDVR0fBDwwOjA4oDag
# NIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RH
# NC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3
# DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEwvb4LyLU0pn/N0IfFiBowf0/Dm1wGc/Do
# 7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8G0iP5kvN2n7Jd2E4/iEIUBO41P5F448r
# SYJ59Ib61eoalhnd6ywFLerycvZTAz40y8S4F3/a+Z1jEMK/DMm/axFSgoR8n6c3
# nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCDA/JYsq7pGdogP8HRtrYfctSLANEBfHU1
# 6r3J05qX3kId+ZOczgj5kjatVB+NdADVZKON/gnZruMvNYY2o1f4MXRJDMdTSlOL
# h0HCn2cQLwQCqjFbqrXuvTPSegOOzr4EWj7PtspIHBldNE2K9i697cvaiIo2p61E
# d2p8xMJb82Yosn0z4y25xUbI7GIN/TpVfHIqQ6Ku/qjTY6hc3hsXMrS+U0yy+GWq
# AXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0c1ugMZyZZd/BdHLiRu7hAWE6bTEm4XYR
# kA6Tl4KSFLFk43esaUeqGkH/wyW4N7OigizwJWeukcyIPbAvjSabnf7+Pu0VrFgo
# iovRDiyx3zEdmcif/sYQsfch28bZeUz2rtY/9TCA6TD8dC3JE3rYkrhLULy7Dc90
# G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz0scmbKvFoW2jNrbM1pD2T7m3XDCCBY0w
# ggR1oAMCAQICEA6bGI750C3n79tQ4ghAGFowDQYJKoZIhvcNAQEMBQAwZTELMAkG
# A1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRp
# Z2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENB
# MB4XDTIyMDgwMTAwMDAwMFoXDTMxMTEwOTIzNTk1OVowYjELMAkGA1UEBhMCVVMx
# FTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNv
# bTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAv+aQc2jeu+RdSjwwIjBpM+zCpyUuySE98orY
# WcLhKac9WKt2ms2uexuEDcQwH/MbpDgW61bGl20dq7J58soR0uRf1gU8Ug9SH8ae
# FaV+vp+pVxZZVXKvaJNwwrK6dZlqczKU0RBEEC7fgvMHhOZ0O21x4i0MG+4g1ckg
# HWMpLc7sXk7Ik/ghYZs06wXGXuxbGrzryc/NrDRAX7F6Zu53yEioZldXn1RYjgwr
# t0+nMNlW7sp7XeOtyU9e5TXnMcvak17cjo+A2raRmECQecN4x7axxLVqGDgDEI3Y
# 1DekLgV9iPWCPhCRcKtVgkEy19sEcypukQF8IUzUvK4bA3VdeGbZOjFEmjNAvwjX
# WkmkwuapoGfdpCe8oU85tRFYF/ckXEaPZPfBaYh2mHY9WV1CdoeJl2l6SPDgohIb
# Zpp0yt5LHucOY67m1O+SkjqePdwA5EUlibaaRBkrfsCUtNJhbesz2cXfSwQAzH0c
# lcOP9yGyshG3u3/y1YxwLEFgqrFjGESVGnZifvaAsPvoZKYz0YkH4b235kOkGLim
# dwHhD5QMIR2yVCkliWzlDlJRR3S+Jqy2QXXeeqxfjT/JvNNBERJb5RBQ6zHFynIW
# IgnffEx1P2PsIV/EIFFrb7GrhotPwtZFX50g/KEexcCPorF+CiaZ9eRpL5gdLfXZ
# qbId5RsCAwEAAaOCATowggE2MA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFOzX
# 44LScV1kTN8uZz/nupiuHA9PMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3z
# bcgPMA4GA1UdDwEB/wQEAwIBhjB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGG
# GGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2Nh
# Y2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDBF
# BgNVHR8EPjA8MDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRBc3N1cmVkSURSb290Q0EuY3JsMBEGA1UdIAQKMAgwBgYEVR0gADANBgkqhkiG
# 9w0BAQwFAAOCAQEAcKC/Q1xV5zhfoKN0Gz22Ftf3v1cHvZqsoYcs7IVeqRq7IviH
# GmlUIu2kiHdtvRoU9BNKei8ttzjv9P+Aufih9/Jy3iS8UgPITtAq3votVs/59Pes
# MHqai7Je1M/RQ0SbQyHrlnKhSLSZy51PpwYDE3cnRNTnf+hZqPC/Lwum6fI0POz3
# A8eHqNJMQBk1RmppVLC4oVaO7KTVPeix3P0c2PR3WlxUjG/voVA9/HYJaISfb8rb
# II01YBwCA8sgsKxYoA5AY8WYIsGyWfVVa88nq2x2zm8jLfR+cWojayL/ErhULSd+
# 2DrZ8LaHlv1b0VysGMNNn3O3AamfV6peKOK5lDGCA3wwggN4AgEBMH0waTELMAkG
# A1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdp
# Q2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1
# IENBMQIQCoDvGEuN8QWC0cR2p5V0aDANBglghkgBZQMEAgEFAKCB0TAaBgkqhkiG
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwHAYJKoZIhvcNAQkFMQ8XDTI1MDgwNTE4NDAx
# MVowKwYLKoZIhvcNAQkQAgwxHDAaMBgwFgQU3WIwrIYKLTBr2jixaHlSMAf7QX4w
# LwYJKoZIhvcNAQkEMSIEIHev+MphAjfxZoyAgC1ckoBIxDygZ7ptrv6/vyuks7hR
# MDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIEqgP6Is11yExVyTj4KOZ2ucrsqzP+Nt
# JpqjNPFGEQozMA0GCSqGSIb3DQEBAQUABIICAE64gswwcWmNsyYmLAOPxO/VyRrz
# 7REiXYaNuHHi7NaUXako4mCodWf2ba4bEiLELOF5f892CCJcl0IZwOMjvhpN5BNd
# 3havnz82NY9/oMas/6QSUMph4sV5lf3Ie/mi8S7G29NG2kjH0dyjVTQ6sF6aZYXR
# J6ULwNDaSv2PIfUe9+N1f5we22ya1aqSK1A2Nt+qg1G59jq2w5KSr+ohMwDPHoDF
# b0eQRAE7lbM4+sorSZeai8c+y5+Lo13SGQF9XWJDMlIEqq/V3SVkgLd7qSM+bxRP
# LUtTv+1N2tWmBWKuqE8hVJu8QSl6aJII4Jrfn+RPraDjm+NyLywHczxKuYJmjxDQ
# f3ncSH/CD49aI+LWKwI9AKBJvjFVoaWLPGRY7HOKiKO2OOaNgJ9cYBHYF/yao3Ne
# BSz2RjYGMvHHpcXAsqLLVbG3AMiK+IdVUNDTWNc5ZLsQGZgbFvZBErrjFopdFnam
# JQflFkQRR824MJk0oOAM7saswWtklKCi71N5tspVsQzud5jBoP2uDtqq0G5/wi4p
# vljBMmJRagWGOpnMMmlacvog4DQspY2C4hctDLUFvd/cow16q4BpeAPq/zqN8TlQ
# hXisNZFa19Tfh15xIVlWrHS5ZFjrdR6t9WKX1JyBThKD37RmHLWnNT1Sz6fz3ZtT
# KtO+dJeDpRhZKSVG
# SIG # End signature block

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
function Get-ColourPalette {
    [CmdletBinding()]
    Param (
        [Parameter()]
        [string]
        $KeyColour = (Get-PSReadLineOption).StringColor,

        [Parameter()]
        [string]
        $StringColour = (Get-PSReadLineOption).ListPredictionColor,

        [Parameter()]
        [string]
        $NumberColour = (Get-PSReadLineOption).NumberColor,
        
        [Parameter()]
        [string]
        $CommentColour = (Get-PSReadLineOption).CommentColor,

        [Parameter()]
        [string]
        $OtherColour = (Get-PSReadLineOption).ParameterColor
    )

    $ColourPalette = [PSCustomObject] @{
        KeyColour     = $KeyColour.SubString(2, 2)
        StringColour  = $StringColour.SubString(2, 2)
        NumberColour  = $NumberColour.SubString(2, 2)
        CommentColour = $CommentColour.SubString(2, 2)
        OtherColour   = $OtherColour.SubString(2, 2)
    }

    return $ColourPalette
}
function Get-PFXFromPem {
    Param (
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]
        $ClientCertificate,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]
        $ClientCertificateFile,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]
        $ClientKey,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]
        $ClientKeyFile
    )

    process {
        if ($ClientCertificate) {
            $CertificateContent = $ClientCertificate
        }
        elseif ($ClientCertificateFile) {
            if (-not (Test-Path $ClientCertificateFile)) {
                Write-Error "ClientCertificateFile '$ClientCertificateFile' not found"
                return
            }
            $CertificateContent = Get-Content -Raw -Path $ClientCertificateFile
        }
        if ($ClientKey) {
            $KeyContent = $ClientKey
        }
        elseif ($ClientKeyFile) {
            if (-not (Test-Path $ClientKeyFile)) {
                Write-Error "ClientKeyFile '$ClientKeyFile' not found"
                return
            }
            $KeyContent = Get-Content -Raw -Path $ClientKeyFile
        }
    
    
        $PemCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem($CertificateContent, $KeyContent)
        $PFXBytes = $PemCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx)
        $PFX = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($PFXBytes)
    
        return $PFX
    }
}
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
function Write-ColourBody {
    Param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Output,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $ContentType,

        [Parameter(Mandatory)]
        [object]
        $ColourPalette,

        [Parameter()]
        [switch]
        $Always
    )

    switch -wildcard ($ContentType) {
        'application/*json*' { Write-ColourJSON -JSON $Output -ColourPalette $ColourPalette }
        'application/*xml*' { Write-Output $Output } # TODO: Write pretty handler
        'application/*html*' { Write-Output $Output } # TODO: Write pretty handler
        'application/*javascript*' { Write-Output $Output } # TODO: Write pretty handler
        'application/x-mpegURL' { Write-Output $Output } # TODO: Write pretty handler
        'multipart/form-data*' { Write-Output $Output }
        'image/svg*' { Write-Output $Output } # TODO: Write XML handler
        'text/*' { Write-Output $Output }
        '' { Write-Output $Output } # For no content-type, try printing directly
        default {
            if ($Always) {
                Write-Output $Output
            }
            else {
                Write-ColourOutput "-- Binary data in format '|-$($ColourPalette.KeyColour)-|$ContentType|-!-|' not shown in terminal --" 
            }
        }
    }
}
function Write-ColourHeaders {
    Param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]
        $Header,

        [Parameter(Mandatory)]
        [object]
        $ColourPalette
    )

    Process {
        Write-ColourOutput "|-$($ColourPalette.KeyColour)-|$($Header.Name)|-!-|: $($Header.Value)"
    }
}
function Write-ColourJSON {
    Param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $JSON,

        [Parameter(Mandatory)]
        [object]
        $ColourPalette
    )

    Begin {
        $CollatedStrings = New-Object -TypeName System.Collections.Generic.List['String']
    }

    Process {
        if ($MyInvocation.ExpectingInput) {
            $CollatedStrings.Add($JSON)
        }
    }

    End {
        if ($CollatedStrings.Count -gt 1) {
            $JSON = $CollatedStrings -Join "`n"
        }

        $EOL = "(?=,*\s*$)"

        # Format JSON
        $FormattedJSON = ConvertFrom-Json -InputObject $JSON | ConvertTo-Json -Depth 100

        # Find keys as any line which starts with a double-quoted string followed by a colon
        $FormattedJSON = $FormattedJSON -Replace '(?m)([ ]+)("[^"\\\n\r]*(?:\\.[^"\\]*)*"(?=:))', "`$1|-$($ColourPalette.KeyColour)-|`$2|-!-|"

        # Find all other sets of characters that the same match but NOT followed by a colon
        $FormattedJSON = $FormattedJSON -replace '(?m)([ ]+)("[^"\\\n\r]*(?:\\.[^"\\]*)*"(?!:))', "`$1|-$($ColourPalette.StringColour)-|`$2|-!-|"

        #Find true/false/null strings that end a line and colorize
        $FormattedJSON = $FormattedJSON -replace "(?m)(true|false|null)$EOL", "|-$($ColourPalette.OtherColour)|`$1|-!-|"

        # Find numbers that end a line and colorize
        $FormattedJSON = $FormattedJSON -replace "(?m)(:[ ]*)(-?[\d\.]+([eE]{1}[+-][\d]+)?)$EOL", "`$1|-$($ColourPalette.NumberColour)-|`$2|-!-|"

        Write-ColourOutput $FormattedJSON
    }
}
function Write-ColourRequest {
    Param(
        [Parameter(Mandatory)]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [string]
        $HttpVersion,

        [Parameter(Mandatory)]
        [System.Uri]
        $ParsedUri,

        [Parameter(Mandatory)]
        [object]
        $ColourPalette
    )

    Write-ColourOutput "|-$($ColourPalette.CommentColour)-|$($Method.ToUpper())|-!-| $($ParsedUri.PathAndQuery) |-$($ColourPalette.CommentColour)-|HTTP|-!-|/|-$($ColourPalette.CommentColour)-|$HttpVersion|-!-|"
}
function Write-ColourStatus {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]
        $RawStatus,

        [Parameter(Mandatory)]
        [object]
        $ColourPalette
    )

    $StatusRegex = '(http|HTTP)\/([\d\.]+) ([\d]{3}) (.*)'
    $StatusMatch = Select-String -InputObject $RawStatus -Pattern $StatusRegex
    if ($StatusMatch) {
        $HTTPPrefix = $StatusMatch.Matches[0].Groups[1].Value
        $HTTPVersion = $StatusMatch.Matches[0].Groups[2].Value
        $StatusCode = $StatusMatch.Matches[0].Groups[3].Value
        $StatusDescription = $StatusMatch.Matches[0].Groups[4].Value

        if ($null -eq $HTTPPrefix -or $null -eq $HTTPVersion -or $null -eq $StatusCode -or $null -eq $StatusDescription) {
            throw "Status code '$RawStatus' is in an unknown format"
        }

        Write-ColourOutput "|-$($ColourPalette.CommentColour)-|$HTTPPrefix|-!-|/|-$($ColourPalette.CommentColour)-|$HTTPVersion |-$($ColourPalette.NumberColour)-|$StatusCode|-!-| $StatusDescription"
    }
    else {
        throw "Status code '$RawStatus' is in an unknown format"
    }
}
<#
.SYNOPSIS
Make an HTTP request and return the output in the desired format.
.DESCRIPTION
Create an HTTP request with user-friendly options for headers, queries and cookies and display the response in the given format. Parameters will result in a call to Invoke-WebRequest, so all IWR parameters are also supported. Note: these may vary based on your version of PowerShell, and will not be validated.
Parameters SkipHeaderValidation and SkipHttpError check are defaulted to $true, and MaximumRedirection is set to 0 so redirects are not chased by default. These can be overridden by supplied parameters if required.
.NOTES
Author: Stuart Macleod (@stuartio)
.PARAMETER Help
Show help and exit
.PARAMETER Uri
Request URI
.PARAMETER Method
Request Method. If a standard HTTP Method the Invoke-WebRequest `Method` parameter will be used. Otherwise the method will be passed to `CustomMethod`. Defaults to 'GET'
.PARAMETER Body
Request body, either as PSCustomObject, hashtable or string. Non-string objects are converted to JSON strings.
.PARAMETER Display
Format to display input and output elements. Can contain one or more of the following options: H - request headers, B - request body, s - response status code and description, S - response status code only, h - response headers, b - response body as string, j - response body JSON string converted to PSCustomObject, x - response body XML converted to XML object. In various circumstances, the text printed to the screen will be coloured according to your shell settings, and will adapt accordingly.
.PARAMETER DisplayParts
Array of integers indicating which multi-part response parts to display. If not specified, all parts will be displayed. If specified, only the parts in the array will be displayed.
.PARAMETER DisplayHeaders
Array of strings indicating which response headers to display. If not specified, all headers will be displayed. If specified, only the headers in the array will be displayed.
.PARAMETER Http1
Use HTTP/1.0
.PARAMETER Http11
Use HTTP/1.1
.PARAMETER Http2
Use HTTP/2
.PARAMETER Http3
Use HTTP/3
.PARAMETER ClientCertificate
String containing base64-encoded public key of your client certificate.
.PARAMETER ClientCertificateFile
File containing base64-encoded public key of your client certificate.
.PARAMETER ClientKey
String containing base64-encoded private key of your client certificate.
.PARAMETER ClientKeyFile
File containing base64-encoded private key of your client certificate.
.PARAMETER Resolve
Replace hostname in your request Uri, but maintain Host header. Analagous to the --resolve option in cURL.
.PARAMETER AdditionalParams
Placeholder parameter for all unnamed params (such as headers, query string parameters and cookies) that you might provide on the command line.
.PARAMETER Authentication
Authentication type to use, either 'None', 'Bearer', 'Basic', 'OAuth', or 'EdgeGrid'. If set to 'Basic' you must provide your username and password with the -Credentials parameter. If set to 'EdgeGrid', the EdgeGrid authentication header will be calculated and added to the request. This requires the additional parameters EdgeRCFile, Section and optionally AccountSwitchKey to be provided. For other authentication methods, see the associated help with Invoke-WebRequest.
.PARAMETER EdgeRCFile
Path to your .edgerc file containing your EdgeGrid credentials when the value of -Authentication is 'EdgeGrid'. If not provided, the default location of ~/.edgerc will be used.
.PARAMETER Section
Section of your .edgerc file to use when the value of -Authentication is 'EdgeGrid'. If not provided, selected section will be 'default'.
.PARAMETER AccountSwitchKey
Account Switch Key to use when the value of -Authentication is 'EdgeGrid'.
#>
function Invoke-Http {
    [CmdletBinding(DefaultParameterSetName = 'h2')]
    [Alias('web')]
    Param(
        [Parameter()]
        [Alias('h')]
        [switch]
        $Help,

        [Parameter(Position = 0)]
        [string]
        $Uri,

        [Parameter()]
        [string]
        $Method = 'GET',

        [Parameter(ParameterSetName = 'h1')]
        [alias('h1')]
        [switch]
        $Http1,

        [Parameter(ParameterSetName = 'h11')]
        [Alias('h11')]
        [switch]
        $Http11,

        [Parameter(ParameterSetName = 'h2')]
        [Alias('h2')]
        [switch]
        $Http2,

        [Parameter(ParameterSetName = 'h3')]
        [Alias('h3')]
        [switch]
        $Http3,

        [Parameter()]
        [string]
        $ClientCertificate,
        
        [Parameter()]
        [string]
        $ClientCertificateFile,
        
        [Parameter()]
        [string]
        $ClientKey,
        
        [Parameter()]
        [string]
        $ClientKeyFile,
        
        [Parameter()]
        [string]
        $Resolve,

        [Parameter()]
        [Alias('d')]
        [string]
        $Display = 'shb',

        [Parameter()]
        [int[]]
        $DisplayParts,

        [Parameter()]
        [string[]]
        $DisplayHeaders,

        [Parameter(ValueFromPipeline)]
        $Body,

        [Parameter(ValueFromRemainingArguments)]
        $AdditionalParams,

        ##-------------------- Default IWR Params beyond this point

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $AllowUnencryptedAuthentication,

        [Parameter()]
        [ValidateSet('None', 'Bearer', 'Basic', 'OAuth', 'EdgeGrid')]
        [string]
        $Authentication,

        [Parameter()]
        [System.Security.Cryptography.X509Certificates.X509Certificate]
        $Certificate,

        [Parameter()]
        [System.String]
        $CertificateThumbprint,

        [Parameter()]
        [System.String]
        $ContentType,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter()]
        [System.String]
        $CustomMethod,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $DisableKeepAlive,

        [Parameter()]
        [System.Collections.IDictionary]
        $Form,

        [Parameter()]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter()]
        [System.Version]
        $HttpVersion,

        [Parameter()]
        [System.String]
        $InFile,

        [Parameter()]
        [System.Int32]
        $MaximumRedirection = 0,

        [Parameter()]
        [System.Int32]
        $MaximumRetryCount,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $NoProxy,

        [Parameter()]
        [System.String]
        $OutFile,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $PassThru,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $PreserveAuthorizationOnRedirect,

        [Parameter()]
        [System.Uri]
        $Proxy = $env:https_proxy,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ProxyCredential,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $ProxyUseDefaultCredentials,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Resume,

        [Parameter()]
        [System.Int32]
        $RetryIntervalSec,

        [Parameter()]
        [System.String]
        $SessionVariable,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $SkipCertificateCheck,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $SkipHeaderValidation,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $SkipHttpErrorCheck,

        [Parameter()]
        [Microsoft.PowerShell.Commands.WebSslProtocol]
        $SslProtocol,

        [Parameter()]
        [System.Int32]
        $TimeoutSec,

        [Parameter()]
        [System.Security.SecureString]
        $Token,

        [Parameter()]
        [System.String]
        $TransferEncoding,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $UseBasicParsing,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $UseDefaultCredentials,

        [Parameter()]
        [System.String]
        $UserAgent,

        [Parameter()]
        [Microsoft.PowerShell.Commands.WebRequestSession]
        $WebSession
    )

    dynamicparam {
        if ($Authentication -and $Authentication.ToLower() -eq 'edgegrid') {
            $paramDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
            
            $EdgeRCAttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $EdgeRCAttribute = New-Object System.Management.Automation.ParameterAttribute
            $EdgeRCAttribute.Mandatory = $false
            $EdgeRCAttributeCollection.Add($EdgeRCAttribute)
            $EdgeRCParam = New-Object System.Management.Automation.RuntimeDefinedParameter('EdgeRCFile', [string], $EdgeRCAttributeCollection)
            $paramDictionary.Add('EdgeRCFile', $EdgeRCParam)
            
            $SectionAttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $SectionAttribute = New-Object System.Management.Automation.ParameterAttribute
            $SectionAttribute.Mandatory = $false
            $SectionAttributeCollection.Add($SectionAttribute)
            $SectionParam = New-Object System.Management.Automation.RuntimeDefinedParameter('Section', [string], $SectionAttributeCollection)
            $paramDictionary.Add('Section', $SectionParam)

            $AccountSwitchKeyAttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $AccountSwitchKeyAttribute = New-Object System.Management.Automation.ParameterAttribute
            $AccountSwitchKeyAttribute.Mandatory = $false
            $AccountSwitchKeyAttributeCollection.Add($AccountSwitchKeyAttribute)
            $AccountSwitchKeyParam = New-Object System.Management.Automation.RuntimeDefinedParameter('AccountSwitchKey', [string], $AccountSwitchKeyAttributeCollection)
            $paramDictionary.Add('AccountSwitchKey', $AccountSwitchKeyParam)

            return $paramDictionary
        }
    }

    process {
        if ($Help) {
            Get-Help Invoke-Http -Detailed
            return
        }


        ### Regexes
        $HeaderParamRegex = '([a-zA-Z0-9\-_]+):'
        $QueryParamRegex = '[a-zA-Z0-9\-_]+='
        $CookieRegex = '[a-zA-Z0-9\-_]+=='

        ### Defaults
        $HeaderForeGround = 'DarkCyan'
        $DefaultHttpVersion = '1.1'

        ### Disable DNS cache
        [System.Net.ServicePointManager]::DnsRefreshTimeout = 0

        ### Set Headers
        $Headers += @{
            'Accept'          = '*/*'
            'Accept-Encoding' = 'gzip,deflate'
            'Connection'      = 'keep-alive'
            'Content-Type'    = 'application/json'
            'User-Agent'      = 'HttPowershell/0.0.1'
        }

        ### Parse Params
        $NamedAdditionalParams = @{}
        $UnnamedAdditionalParams = New-Object -TypeName System.Collections.Generic.List['String']
        $AdditionalQueryParams = New-Object -TypeName System.Collections.Generic.List['String']
        $AdditionalRequestCookies = New-Object -TypeName System.Collections.Generic.List['String']
        for ($i = 0; $i -lt $AdditionalParams.count; $i++) {
            # Capture params starting with -, where there is a next item in the list but it does not start with -
            if ($AdditionalParams[$i].StartsWith('-') -and -not (($i + 1) -eq $AdditionalParams.count) -and -not $AdditionalParams[$i + 1].StartsWith('-')) {
                $ParamName = $AdditionalParams[$i].SubString(1)
                $ParamValue = $AdditionalParams[++$i]
                $NamedAdditionalParams[$ParamName] = $ParamValue
            }
            # Else if param starts with - add as switch
            elseif ($AdditionalParams[$i].StartsWith('-')) {
                $ParamName = $AdditionalParams[$i].SubString(1)
                $NamedAdditionalParams[$ParamName] = $true
            }
            # Otherwise add as unnamed param and parse
            else {
                $UnnamedAdditionalParams.Add($AdditionalParams[$i])
            }
        }

        ### Parse Unnamed params
        foreach ($Param in $UnnamedAdditionalParams) {
            if ($Param -match $HeaderParamRegex) {
                # Separate name and value, and encode value back to ascii
                $HeaderValue = $Param.Replace($Matches[0], '').Trim()
                if ('' -eq $HeaderValue) {
                    Write-Debug "---- Removing request header $($Matches[1])"
                    $Headers.Remove($Matches[1])
                }
                else {
                    $HeaderValue = ConvertTo-UTF8 -InputObject $HeaderValue
                    $Headers[$Matches[1]] = $Param.Replace($Matches[0], '').Trim()
                }
            }
            elseif ($Param -match $CookieRegex) {
                # Add to array but replace == with =
                $AdditionalRequestCookies.Add($Param.Replace('==', '='))
            }
            elseif ($Param -match $QueryParamRegex) {
                $AdditionalQueryParams.Add($Param)
            }
        }

        ### Append any additional query params found
        if ($AdditionalQueryParams.count -gt 0) {
            $JoinedParams = $AdditionalQueryParams -Join '&'
            if ($Uri.contains('?')) {
                $Uri += "&$JoinedParams"
            }
            else {
                $Uri += "?$JoinedParams"
            }
        }

        ### Append any additional cookies found
        if ($AdditionalRequestCookies.count -gt 0) {
            $ExistingCookieHeader = $Headers['cookie']
            $JoinedAdditionalCookies = $AdditionalRequestCookies -join ';'
            $CookieJoiner = ''
            if ($null -ne $ExistingCookieHeader) {
                # If cookies exist join with semi-colon
                $CookieJoiner = ';'
            }
            $Headers['cookie'] += "$CookieJoiner$JoinedAdditionalCookies"
        }

        ### Format request body, as it may be needed for signing
        $RequestBody = $null
        if ($null -ne $PSBoundParameters.Body) {
            $RequestBody = Get-BodyString -Body $Body
        }

        ### Calculate auth header if authentication == edgegrid
        if ($Authentication -and $Authentication.ToLower() -eq 'edgegrid') {
            $CredentialParams = @{
                EdgeRCFile       = $PSBoundParameters.EdgeRCFile
                Section          = $PSBoundParameters.Section
                AccountSwitchKey = $PSBoundParameters.AccountSwitchKey
            }
            $Credentials = Get-AkamaiCredentials @CredentialParams
            $AkamaiAuthParams = @{
                Credentials  = $Credentials
                Method       = $Method
                ExpandedPath = $Uri
            }

            if ($RequestBody) { $AkamaiAuthParams.Body = $RequestBody }
            if ($InFile) { $AkamaiAuthParams.InputFile = $InputFile }

            $AkamaiAuthHeader = Get-AkamaiAuthHeader @AkamaiAuthParams
            Write-Debug "Akamai auth header: $AkamaiAuthHeader"
            $Headers['Authorization'] = $AkamaiAuthHeader

            ## Add ASK
            if ($Credentials.AccountSwitchKey) {
                if ($Uri.Contains('?')) {
                    $Uri += "&"
                }
                else {
                    $Uri += "?"
                }
                $Uri += "accountSwitchKey=$($Credentials.AccountSwitchKey)"
            }

            $Uri = "https://$($Credentials.host)$Uri"
        }

        ### Parsed URI
        if ($Uri -notmatch '^https?://') {
            # Prepend protocol
            $Uri = "https://$Uri"
        }
        $ParsedURI = [System.Uri] $Uri

        # Add host header
        $Headers['Host'] = $ParsedURI.Host

        ### Resolve
        if ($Resolve) {
            if ($Resolve.ToLower() -eq 'akamaistaging') {
                $Resolve = Get-AkamaiStagingIP -Hostname $ParsedURI.Host
            }
            $Uri = $Uri.Replace($ParsedURI.Host, $Resolve)
        }

        ### Select protocol if not provided
        if (-not ($Uri -match '^(http|HTTP)[sS]?:\/\/.*')) {
            $Uri = "https://$Uri"
        }

        ### Parse Http Version
        if ($null -eq $PSBoundParameters.HttpVersion) {
            $HttpVersion = $DefaultHttpVersion
        }
        if ($Http1) {
            $HttpVersion = '1.0'
        }
        elseif ($Http11) {
            $HttpVersion = '1.1'
        }
        elseif ($Http2) {
            $HttpVersion = '2.0'
        }
        elseif ($HTT3) {
            $HttpVersion = '3.0'
        }

        ## Handle overridden erroraction
        $ErrorAction = 'stop'
        if ($PSBoundParameters.ErrorAction) {
            $ErrorAction = $PSBoundParameters.ErrorAction
        }

        ## Handle skip switches to true
        if ($null -eq $PSBoundParameters.SkipHeaderValidation) {
            $SkipHeaderValidation = $true
        }
        if ($null -eq $PSBoundParameters.SkipHttpErrorCheck) {
            $SkipHttpErrorCheck = $true
        }

        # Splat IWR params
        $IWRParams = @{
            Uri                  = $Uri
            Headers              = $Headers
            MaximumRedirection   = $MaximumRedirection
            SkipHeaderValidation = $SkipHeaderValidation
            SkipHttpErrorCheck   = $SkipHttpErrorCheck
            Proxy                = $Proxy
            HttpVersion          = $HttpVersion
            ErrorAction          = $ErrorAction
            DisableKeepAlive     = $true
        }
        # Add additional params to IWRParams
        $NonIWRParams = @(
            'Display',
            'DisplayParts',
            'DisplayHeaders',
            'http1',
            'http11',
            'http2',
            'http3',
            'AdditionalParams',
            'Key',
            'Debug',
            'ClientCertificate',
            'ClientCertificateFile',
            'ClientKey',
            'ClientKeyFile',
            'Resolve',
            'EdgeRCFile',
            'Section',
            'AccountSwitchKey'
        )
        if ($Authentication -eq 'EdgeGrid') {
            $NonIWRParams += 'Authentication'
        }

        $PSBoundParameters.Keys  | ForEach-Object {
            if ($_ -notin $NonIWRParams -and $_ -notin $IWRParams.Keys) {
                $IWRParams.$_ = $PSBoundParameters.$_
            }
        }

        ### Parse method
        $DefaultMethods = 'DEFAULT', 'DELETE', 'GET', 'HEAD', 'MERGE', 'OPTIONS', 'PATCH', 'POST', 'PUT', 'TRACE'
        if ($Method -in $DefaultMethods) {
            $IWRParams.Method = $Method
            $IWRParams.Remove('CustomMethod')
        }
        else {
            $IWRParams.CustomMethod = $Method
            $IWRParams.Remove('Method')
        }

        ### Parse Body
        if ($null -ne $RequestBody) {
            $IWRParams.Body = $RequestBody
        }

        ### Load Client Cert
        if ($ClientCertificate -or $ClientCertificateFile) {
            if ($null -eq $PSBoundParameters.ClientKey -and $null -eq $PSBoundParameters.ClientKeyFile) {
                Write-Error "When using -ClientCertificate or -ClientCertificateFile you must provide one of: -ClientKey, -ClientKeyFile"
                return
            }
            
            $IWRParams.Certificate = $PSBoundParameters | Select-Object ClientCertificate, ClientCertificateFile, ClientKey, ClientKeyFile | Get-PFXFromPem
        }

        # Add -PassThru if OutFile present
        if ($OutFile) {
            $IWRParams.PassThru = $true
        }

        Write-Debug "IWRParams:"
        Write-Debug ($IWRParams | ConvertTo-Json -Depth 100)

        #### ---- Request Output
        if ($Display) {
            ## Process colour pallette
            $ColourPalette = Get-ColourPalette

            ## Request Headers
            if ($Display.contains('H')) {
                # Format headers hashtable into array of objects
                $RequestHeaders = $Headers.Keys | ForEach-Object {
                    [PSCustomObject] @{ Name = $_; Value = $Headers[$_] }
                }

                Write-ColourRequest -Method $Method -HttpVersion $HttpVersion -ParsedUri $ParsedURI -ColourPalette $ColourPalette
                $RequestHeaders | Write-ColourHeaders -ColourPalette $ColourPalette
                # Add new line
                Write-Output ""
            }

            ### Request Body
            if ($Display.contains('B')) {
                if ($RequestBody) {
                    Write-ColourBody -Output $RequestBody -ContentType $Headers['content-type'] -ColourPalette $ColourPalette
                    # Add new line
                    # Write-Output ""
                }
            }
        }

        ## ---- Backup and set ProgressPreference
        $OldProgressPreference = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'

        ### ---- Make request
        $AnErrorHasOccurred = $false # Track this explicitly to avoid higher-level or old instances of $ResponseError causing the throw
        $ResponseTime = Measure-Command { 
            $Response = try {
                Invoke-WebRequest @IWRParams
            }
            catch {
                $AnErrorHasOccurred = $true
                $ResponseError = $_
            }
        }

        ### Handle errors
        if ($AnErrorHasOccurred) {
            $ErrorsToSkip = @(
                'The maximum redirection count has been exceeded. To increase the number of redirections allowed, supply a higher value to the -MaximumRedirection parameter.'
            )
            if ($ResponseError.ErrorDetails.Message -notin $ErrorsToSkip) {
                return $ResponseError
            }
        }

        ## ---- Reset ProgressPreference
        $ProgressPreference = $OldProgressPreference
        
        ### ---- Response Output
        if ($Display) {
            $FormattedResponse = Format-Response -RawResponse $Response.RawContent -DisplayHeaders $DisplayHeaders

            # Replace body element if -OutFile specified
            if ($OutFile -and -not $PSBoundParameters.Display) {
                $Display = $Display.replace("b", "")
            }

            ### Status
            if ($Display.contains('S')) {
                Write-ColourOutput "|-$($ColourPalette.NumberColour)-|$($FormattedResponse.StatusCode)|-!-|"
            }
            if ($Display.contains('s')) {
                Write-ColourStatus $FormattedResponse.Status -ColourPalette $ColourPalette
            }

            ## Response Headers
            if ($Display.contains('h')) {
                $FormattedResponse.Headers | Write-ColourHeaders -ColourPalette $ColourPalette
                Write-Output ""

                for ($p = 1; $p -le $FormattedResponse.Parts.count; $p++) {
                    if ($null -ne $PSBoundParameters.DisplayParts -and $p -notin $DisplayParts ) {
                        continue
                    }

                    Write-ColourOutput "|-green-|Multi-Part Headers:|-!-|"
                    $FormattedResponse.Parts[$p - 1].Headers | Write-ColourHeaders -ColourPalette $ColourPalette
                    # Add new line
                    Write-Output ""
                }
            }
            
            ## Response Body
            if ($Display.contains('b')) {
                if ($FormattedResponse.Body) {
                    Write-ColourBody -Output $FormattedResponse.Body -ContentType $FormattedResponse.ContentType -ColourPalette $ColourPalette
                    # Add new line
                    # Write-Output ""
                }
                
                for ($p = 1; $p -le $FormattedResponse.Parts.count; $p++) {
                    if ($null -ne $PSBoundParameters.DisplayParts -and $p -notin $DisplayParts ) {
                        continue
                    }
                    
                    Write-ColourOutput "|-green-|Multi-Part Body:|-!-|"
                    $Part = $FormattedResponse.Parts[$p - 1]
                    Write-ColourBody -Output $Part.Body -ContentType $Part.ContentType -ColourPalette $ColourPalette
                    # Add new line
                    # Write-Output ""
                }
            }

            ## All
            if ($Display.contains('a')) {
                if ($FormattedResponse.Body) {
                    Write-Host "Main body" -ForegroundColor green
                    Write-ColourBody -Output $FormattedResponse.Body -ContentType $FormattedResponse.ContentType -Always -ColourPalette $ColourPalette
                    # Add new line
                    # Write-Output ""
                }
                
                foreach ($Part in $FormattedResponse.Parts) {
                    Write-Host "Multi-part body" -ForegroundColor green
                    Write-ColourOutput "|-green-|Multi-Part Body:|-!-|"
                    Write-ColourBody -Output $Part.Body -ContentType $Part.ContentType -Always -ColourPalette $ColourPalette
                    # Add new line
                    # Write-Output ""
                }
            }

            ## Raw
            if ($Display.contains('r')) {
                Write-Output $Response.RawContent
            }

            ## JSON Object
            if ($Display.contains('j')) {
                try {
                    $BodyObject = $FormattedResponse.Body | ConvertFrom-Json
                    Write-Output $BodyObject
                }
                catch {
                    Write-Debug "Failed to convert response body of type '$ResponseContentType' to object"
                    Write-Output $FormattedResponse.Body
                }
                # Add new line
                # Write-Output ""
            }

            ## XML Object
            if ($Display.contains('x')) {
                try {
                    $BodyObject = [xml] $FormattedResponse.Body
                    Write-Output $BodyObject
                }
                catch {
                    Write-Debug "Failed to convert response body of type '$ResponseContentType' to object"
                    Write-Output $FormattedResponse.Body
                }
                # Add new line
                # Write-Output ""
            }

            ## Response Time
            if ($Display.Contains('t')) {
                Write-ColourOutput "|-$($ColourPalette.StringColour)-|Total Milliseconds|-!-|: $($ResponseTime.TotalMilliseconds)"
            }
            if ($Display.Contains('T')) {
                $ResponseTime
            }
        }
        else {
            return $Response
        }
    }

}
