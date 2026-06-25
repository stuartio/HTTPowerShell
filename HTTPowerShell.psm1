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
function Get-AkamaiStagingIP {
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
function Get-EdgegridAuthHeader {
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
    $SignatureData += "client_token=" + $Credentials.ClientToken + ";"
    $SignatureData += "access_token=" + $Credentials.AccessToken + ";"
    $SignatureData += "timestamp=" + $TimeStamp + ";"
    $SignatureData += "nonce=" + $Nonce + ";"

    Write-Debug "SignatureData = $SignatureData"

    # Generate SigningKey
    $SigningKey = Get-EncryptedMessage -secret $Credentials.ClientSecret -message $TimeStamp

    # Generate Auth Signature
    $Signature = Get-EncryptedMessage -secret $SigningKey -message $SignatureData

    # Create AuthHeader
    $AuthorizationHeader = "EG1-HMAC-SHA256 "
    $AuthorizationHeader += "client_token=" + $Credentials.ClientToken + ";"
    $AuthorizationHeader += "access_token=" + $Credentials.AccessToken + ";"
    $AuthorizationHeader += "timestamp=" + $TimeStamp + ";"
    $AuthorizationHeader += "nonce=" + $Nonce + ";"
    $AuthorizationHeader += "signature=" + $Signature

    return $AuthorizationHeader
}
function Get-EdgegridCredentials {
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
    #                             1. Set up auth object
    #----------------------------------------------------------------------------------------------

    ## Instantiate auth object
    $Credentials = [PSCustomObject] @{
        Host         = $null
        ClientToken  = $null
        AccessToken  = $null
        ClientSecret = $null
        AccountKey   = $null
    }

    #----------------------------------------------------------------------------------------------
    #                              2. Check for environment variables
    #----------------------------------------------------------------------------------------------

    ## 'default' section is implicit. Otherwise env variable starts with section prefix
    if ($Mode -ne 'edgerc') {
        if ($Section.ToLower() -eq 'default') {
            $EnvPrefix = 'AKAMAI'
        }
        else {
            $EnvPrefix = "AKAMAI_$Section".ToUpper()
        }

        if (Test-Path "env:\$EnvPrefix`_HOST") {
            $Credentials.Host = (Get-Item -Path "env:\$EnvPrefix`_HOST").Value
        }
        if (Test-Path "env:\$EnvPrefix`_CLIENT_TOKEN") {
            $Credentials.ClientToken = (Get-Item -Path "env:\$EnvPrefix`_CLIENT_TOKEN").Value
        }
        if (Test-Path "env:\$EnvPrefix`_ACCESS_TOKEN") {
            $Credentials.AccessToken = (Get-Item -Path "env:\$EnvPrefix`_ACCESS_TOKEN").Value
        }
        if (Test-Path "env:\$EnvPrefix`_CLIENT_SECRET") {
            $Credentials.ClientSecret = (Get-Item -Path "env:\$EnvPrefix`_CLIENT_SECRET").Value
        }
        if (Test-Path "env:\$EnvPrefix`_ACCOUNT_KEY") {
            $Credentials.AccountKey = (Get-Item -Path "env:\$EnvPrefix`_ACCOUNT_KEY").Value
        }

        ## Explicit ASK wins over env variable
        if ($AccountSwitchKey) {
            $Credentials.AccountKey = $AccountSwitchKey
        }

        ## Remove ASK if value is "none"
        if ($AccountSwitchKey -eq "none") {
            $Credentials.AccountKey = $null
        }

        ## Check essential elements and return
        if ($null -ne $Credentials.Host -and $null -ne $Credentials.ClientToken -and $null -ne $Credentials.AccessToken -and $null -ne $Credentials.ClientSecret) {
            ## Env creds valid
            Write-Debug "Obtained credentials from environment variables in section '$Section'"
            return $Credentials
        }
    }

    #----------------------------------------------------------------------------------------------
    #                              3. Read from .edgerc file
    #----------------------------------------------------------------------------------------------

    # Get credentials from EdgeRC
    if (Test-Path $EdgeRCFile) {
        $EdgeRCContent = Get-Content $EdgeRCFile -Raw
        $SectionPattern = "(?s)(\[$Section\].*?)(\[|$)"
        $SectionMatch = $EdgeRCContent | Select-String -Pattern $SectionPattern

        if ($SectionMatch -and $SectionMatch.Matches[0].Groups[1].Value) {
            $SectionContent = $SectionMatch.Matches[0].Groups[1].Value

            $HostMatch = $SectionContent | Select-String -Pattern "\r?\nhost[ ]*=[ ]*([^\s#]+)"
            if ($HostMatch) {
                $Credentials.host = $HostMatch.Matches[0].Groups[1].Value
            }
            $ClientTokenMatch = $SectionContent | Select-String -Pattern "\r?\nclient_token[ ]*=[ ]*([^\s#]+)"
            if ($ClientTokenMatch) {
                $Credentials.ClientToken = $ClientTokenMatch.Matches[0].Groups[1].Value
            }
            $AccessTokenMatch = $SectionContent | Select-String -Pattern "\r?\naccess_token[ ]*=[ ]*([^\s#]+)"
            if ($AccessTokenMatch) {
                $Credentials.AccessToken = $AccessTokenMatch.Matches[0].Groups[1].Value
            }
            $ClientSecretMatch = $SectionContent | Select-String -Pattern "\r?\nclient_secret[ ]*=[ ]*([^\s#]+)"
            if ($ClientSecretMatch) {
                $Credentials.ClientSecret = $ClientSecretMatch.Matches[0].Groups[1].Value
            }
            $AccountKeyMatch = $SectionContent | Select-String -Pattern "\r?\naccount_key[ ]*=[ ]*([^\s#]+)"
            if ($AccountKeyMatch) {
                $Credentials.AccountKey = $AccountKeyMatch.Matches[0].Groups[1].Value
            }
        }
        else {
            throw "Error: Section '$Section' not found in edgerc file '$EdgeRCFile'"
        }

        ## Explicit ASK wins over edgerc file entry
        if ($AccountSwitchKey) {
            $Credentials.AccountKey = $AccountSwitchKey
        }

        ## Remove ASK if value is "none"
        if ($AccountSwitchKey -eq "none") {
            $Credentials.AccountKey = $null
        }

        ## Check essential elements and return
        if ($null -ne $Credentials.host -and $null -ne $Credentials.ClientToken -and $null -ne $Credentials.AccessToken -and $null -ne $Credentials.ClientSecret) {
            Write-Debug "Obtained credentials from edgerc file '$EdgeRCFile' in section '$Section'"
            return $Credentials
        }
    }

    #----------------------------------------------------------------------------------------------
    #                                     4. Panic!
    #----------------------------------------------------------------------------------------------

    ## Under normal circumstances you should not get this far...
    throw "Error: Credentials could not be loaded from either; session, environment variables or edgerc file '$EdgeRCFile'"

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
function Resolve-GoogleDNS {
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
function Invoke-Http {
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
            $Credentials = Get-EdgeGridCredentials @CredentialParams
            $EdgegridAuthParams = @{
                Credentials  = $Credentials
                Method       = $Method
                ExpandedPath = $Uri
            }

            if ($RequestBody) { $EdgegridAuthParams.Body = $RequestBody }
            if ($InFile) { $EdgegridAuthParams.InputFile = $InputFile }

            $EdgeGridAuthHeader = Get-EdgeGridAuthHeader @EdgegridAuthParams
            Write-Debug "EdgeGrid auth header: $EdgeGridAuthHeader"
            $Headers['Authorization'] = $EdgeGridAuthHeader

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
