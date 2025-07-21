<#
.SYNOPSIS
Make HTTP request
.DESCRIPTION
Create an HTTP request with user-friendly options for headers, queries and cookies and display the response in the given format. Parameters will result in a call to Invoke-WebRequest, so all IWR parameters are also supported. Note: these may vary based on your version of PowerShell, and will not be validated.
Parameters SkipHeaderValidation and SkipHttpError check are defaulted to $true, and MaximumRedirection is set to 0 so redirects are not chased by default. These can be overridden by supplied parameters if required.
.NOTES
Author: Stuart Macleod (@stuartio)
.PARAMETER Uri
Request URI
.PARAMETER Method
Request Method. If a standard HTTP Method the Invoke-WebRequest `Method` parameter will be used. Otherwise the method will be passed to `CustomMethod`. Defaults to 'GET'
.PARAMETER Body
Request body, either as PSCustomObject, hashtable or string. Non-string objects are converted to JSON strings.
.PARAMETER Display
Format to display input and output elements. Can contain one or more of the following options: H - request headers, B - request body, s - response status code and description, S - response status code only, h - response headers, b - response body as string, j - response body JSON string converted to PSCustomObject, x - response body XML converted to XML object. In various circumstances, the text printed to the screen will be coloured according to your shell settings, and will adapt accordingly.
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
.PARAMETER RouteTo
Replace hostname in your request Uri, but maintain Host header. Analagous to the --resolve option in cURL.
.PARAMETER AdditionalParams
Placeholder parameter for all unnamed params (such as headers, query string parameters and cookies) that you might provide on the command line.
#>
function Invoke-Http {
    [CmdletBinding(DefaultParameterSetName = 'h2')]
    [Alias('web')]
    Param(
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
        $RouteTo,

        [Parameter()]
        [Alias('d')]
        [string]
        $Display = 'shb',

        [Parameter(ValueFromPipeline)]
        $Body,

        [Parameter(ValueFromRemainingArguments)]
        $AdditionalParams,

        ##-------------------- Default IWR Params beyond this point

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $AllowUnencryptedAuthentication,

        [Parameter()]
        [Microsoft.PowerShell.Commands.WebAuthenticationType]
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

    process {
        ### Regexes
        $HeaderParamRegex = '([a-zA-Z0-9\-_]+):'
        $QueryParamRegex = '[a-zA-Z0-9\-_]+='
        $CookieRegex = '[a-zA-Z0-9\-_]+=='

        ### Defaults
        $HeaderForeGround = 'DarkCyan'
        $DefaultHttpVersion = '1.1'

        ### Disable DNS cache
        [System.Net.ServicePointManager]::DnsRefreshTimeout = 0

        ### Parsed URI
        if ($Uri -notmatch '^https?://') {
            # Prepend protocol
            $Uri = "https://$Uri"
        }
        $ParsedURI = [System.Uri] $Uri

        $Headers += @{
            'Accept'          = '*/*'
            'Accept-Encoding' = 'gzip,deflate'
            'Connection'      = 'keep-alive'
            'Content-Type'    = 'application/json'
            'Host'            = $ParsedURI.Host
            'User-Agent'      = 'HttPowershell/0.0.1'
        }

        ### RouteTo
        if ($RouteTo) {
            $Uri = $Uri.Replace($ParsedURI.Host, $RouteTo)
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
                    $HeaderValue = ConvertTo-ASCII -InputObject $HeaderValue
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
        $NonIWRParams = 'Display', 'http1', 'http11', 'http2', 'http3', 'AdditionalParams', 'Key', 'Debug', 'ClientCertificate', 'ClientCertificateFile', 'ClientKey', 'ClientKeyFile', 'RouteTo'
        $PSBoundParameters.Keys  | ForEach-Object {
            if ($_ -notin $NonIWRParams -and $_ -notin $IWRParams.Keys) {
                $IWRParams.$_ = $PSBoundParameters.$_
            }
        }

        ### Parse method
        $DefaultMethods = 'DEFAULT', 'DELETE', 'GET', 'HEAD', 'MERGE', 'OPTIONS', 'PATCH', 'POST', 'PUT', 'TRACE'
        if ($Method -in $DefaultMethods) {
            $IWRParams.Method = $Method
        }
        else {
            $IWRParams.CustomMethod = $Method
        }

        ### Parse Body
        if ($null -ne $PSBoundParameters.Body) {
            $RequestBody = Get-BodyString -Body $Body
            $IWRParams.Body = $RequestBody
        }

        ### Load Client Cert
        if ($ClientCertificate -or $ClientCertificateFile) {
            if ($null -eq $PSBoundParameters.ClientKey -and $null -eq $PSBoundParameters.ClientKeyFile) {
                Write-Error "When using -ClientCertificate or -ClientCertificateFile you must provide one of: -ClientKey, -ClientKeyFile"
                return
            }
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
            $IWRParams.Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem($CertificateContent, $KeyContent)
        }

        # Add -PassThru if OutFile present
        if ($OutFile) {
            $IWRParams.PassThru = $true
        }

        Write-Debug "IWRParams:"
        Write-Debug ($IWRParams | ConvertTo-Json -Depth 100)

        #### ---- Request Output
        if ($Display) {
            ## Request Headers
            if ($Display.contains('H')) {
                # Format headers hashtable into array of objects
                $RequestHeaders = $Headers.Keys | ForEach-Object {
                    [PSCustomObject] @{ Name = $_; Value = $Headers[$_] }
                }

                Write-Request -Method $Method -HttpVersion $HttpVersion -ParsedUri $ParsedURI
                $RequestHeaders | Write-ColourfulHeaders
                # Add new line
                Write-Output ""
            }

            ### Request Body
            if ($Display.contains('B')) {
                if ($RequestBody) {
                    Write-ColourfulOutput -Output $RequestBody -ContentType $Headers['content-type']
                    # Add new line
                    Write-Output ""
                }
            }
        }

        ## ---- Backup and set ProgressPreference
        $OldProgressPreference = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'

        ### ---- Make request
        $AnErrorHasOccurred = $false # Track this explicitly to avoid higher-level or old instances of $ResponseError causing the throw
        $Response = try {
            Invoke-WebRequest @IWRParams
        }
        catch {
            $AnErrorHasOccurred = $true
            $ResponseError = $_
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
            ### Parse response. Have to use raw as we want to show multiple items for when headers are duplicated
            $RawResponse = $Response.RawContent -split "`r`n"
            $ResponseHeaders = New-Object -TypeName System.Collections.Generic.List['HashTable']
            for ($i = 1; $i -lt $RawResponse.count; $i++) {
                if ($RawResponse[$i] -match $HeaderParamRegex) {
                    $ResponseHeaders.Add(@{
                            name  = $Matches[1]
                            value = $RawResponse[$i].Replace($Matches[0], '').Trim()
                        })
                }
                else {
                    if ($RawResponse[$i] -eq '') {
                        break
                    }
                    else {
                        throw "Response header $($RepsonseContent[$i]) appears to be malformed"
                    }
                }
            }
            # Sort headers
            $ResponseHeaders = $ResponseHeaders | Sort-Object -Property Name, Value
            $ResponseContentType = $ResponseHeaders |
            Where-Object { $_.name.ToLower() -eq 'content-type' } |
            Select-Object -First 1 |
            Select-Object -ExpandProperty value
            # Assign response body
            $ResponseBody = $Response.Content
            # Handle byte[] response type
            if ($ResponseBody -is 'byte[]') {
                $ResponseBody = [System.Text.Encoding]::UTF8.GetString($ResponseBody)
            }

            ### Status
            if ($Display.contains('S')) {
                Write-Host -ForegroundColor $HeaderForeGround $Response.StatusCode
            }
            if ($Display.contains('s')) {
                Write-StatusCode $RawResponse[0]
            }

            ## Response Headers
            if ($Display.contains('h')) {
                $ResponseHeaders | Write-ColourfulHeaders
                Write-Output ""
            }
            
            ## Response Body
            if ($Display.contains('b')) {
                Write-ColourfulOutput -Output $ResponseBody -ContentType $ResponseContentType
                # Add new line
                Write-Output ""
            }
            if ($Display.contains('j')) {
                try {
                    $BodyObject = $ResponseBody | ConvertFrom-Json
                    Write-Output $BodyObject
                }
                catch {
                    Write-Debug "Failed to convert response body of type '$ResponseContentType' to object"
                    Write-Output $ResponseBody
                }
                # Add new line
                Write-Output ""
            }
            if ($Display.contains('x')) {
                try {
                    $BodyObject = [xml] $ResponseBody
                    Write-Output $BodyObject
                }
                catch {
                    Write-Debug "Failed to convert response body of type '$ResponseContentType' to object"
                    Write-Output $ResponseBody
                }
                # Add new line
                Write-Output ""
            }
        }
        else {
            return $Response
        }
    }

}