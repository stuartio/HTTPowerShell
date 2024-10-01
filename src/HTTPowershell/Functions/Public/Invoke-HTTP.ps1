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
        [Alias('h1.1')]
        [switch]
        ${Http1.1},

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
        $Certificate,

        [Parameter()]
        [string]
        $Key,

        [Parameter()]
        [Alias('o')]
        [string]
        $Output = 'hb',

        [Parameter(ValueFromPipeline)]
        $Body,

        [Parameter(ValueFromRemainingArguments)]
        $AdditionalParams
    )

    process {
        ### Regexes
        $HeaderParamRegex = '([a-zA-Z0-9\-]+):'
        $QueryParamRegex = '[a-zA-Z0-9\-]+='
        $CookieRegex = '[a-zA-Z0-9\-]+=='

        ### Defaults
        $HeaderForeGround = 'DarkCyan'
        $DefaultHttpVersion = '1.1'

        ### Parsed URI
        $ParsedURI = [System.Uri] $Uri

        $RequestHeaders = @{
            'Accept'          = '*/*'
            'Accept-Encoding' = 'gzip,deflate'
            'Connection'      = 'keep-alive'
            'Content-Type'    = 'application/json'
            'Host'            = $ParsedURI.Host
            'User-Agent'      = 'HttPowershell/0.0.1'
        }

        ### Parse Params
        Write-Debug "AdditionalParams:"
        Write-Debug ($AdditionalParams | ConvertTo-Json)
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
                $HeaderValue = ConvertTo-ASCII -InputObject $HeaderValue
                $RequestHeaders[$Matches[1]] = $Param.Replace($Matches[0], '').Trim()
            }
            elseif ($Param -match $QueryParamRegex) {
                $AdditionalQueryParams.Add($Param)
            }
            elseif ($Param -match $CookieRegex) {
                # Add to array but replace == with =
                $AdditionalRequestCookies.Add($Param.Replace('==', '='))
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
            $ExistingCookieHeader = $RequestHeaders['cookie']
            $JoinedAdditionalCookies = $AdditionalRequestCookies -join ';'
            $CookieJoiner = ''
            if ($null -ne $ExistingCookieHeader) {
                # If cookies exist join with semi-colon
                $CookieJoiner = ';'
            }
            $RequestHeaders['cookie'] += "$CookieJoiner$JoinedAdditionalCookies"
        }

        ### Select protocol if not provided
        if (-not ($Uri -match '^(http|HTTP)[sS]?:\/\/.*')) {
            $Uri = "https://$Uri"
        }

        ### Parse Http Version
        $HttpVersion = $DefaultHttpVersion
        if ($Http1) {
            $HttpVersion = '1.0'
        }
        elseif (${Http1.1}) {
            $HttpVersion = '1.1'
        }
        elseif ($Http2) {
            $HttpVersion = '2.0'
        }
        elseif ($HTT3) {
            $HttpVersion = '3.0'
        }

        # Splat IWR params
        $IWRParams = @{
            Uri                  = $Uri
            Headers              = $RequestHeaders
            MaximumRedirection   = 0
            SkipHeaderValidation = $true
            SkipHttpErrorCheck   = $true
            Proxy                = $env:https_proxy
            HttpVersion          = $HttpVersion
            ErrorAction          = 'stop'
        }
        # Add named additional args
        foreach ($NamedArgKey in $NamedAdditionalParams.Keys) {
            $IWRParams[$NamedArgKey] = $NamedAdditionalParams[$NamedArgKey]
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

        Write-Debug "IWRParams:"
        Write-Debug ($IWRParams | ConvertTo-Json)

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

        
        ### ---- Output
        if ($Output) {
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
            # Assign response body
            $ResponseBody = $Response.Content
            # Handle byte[] response type
            if ($ResponseBody -is 'byte[]') {
                $ResponseBody = [System.Text.Encoding]::UTF8.GetString($ResponseBody)
            }
            
            ## Request Headers
            if ($Output.contains('H')) {
                Write-Request -Method $Method -HttpVersion $HttpVersion -ParsedUri $ParsedURI
                $RequestHeaders.Keys | Sort-Object | ForEach-Object {
                    Write-Host -ForegroundColor $HeaderForeGround -NoNewline $_
                    Write-Host ": $($RequestHeaders.$_)"
                }
                # Add new line
                Write-Host ""
            }

            ### Request Body
            if ($Output.contains('B')) {
                Write-ColourfulOutput -Output $RequestBody -ContentType $RequestHeaders['content-type']
                # Add new line
                Write-Host ""
            }

            ## Response Headers
            if ($Output.contains('h')) {
                Write-StatusCode $RawResponse[0]
                $ResponseHeaders | ForEach-Object {
                    Write-Host -ForegroundColor $HeaderForeGround -NoNewline $_.Name
                    Write-Host ": $($_.Value)"
                }
                # Add new line
                Write-Host ""
            }
            
            ## Response Body
            if ($Output.contains('b')) {
                Write-ColourfulOutput -Output $ResponseBody -ContentType $ResponseHeaders['content-type']
                # Add new line
                Write-Host ""
            }
            if ($Output.contains('j')) {
                try {
                    $BodyObject = $ResponseBody | ConvertFrom-Json
                    Write-Output $BodyObject
                }
                catch {
                    Write-Debug "Failed to convert response body of type '$($ResponseHeaders['content-type'])' to object"
                    Write-Output $ResponseBody
                }
                # Add new line
                Write-Host ""
            }
            if ($Output.contains('x')) {
                try {
                    $BodyObject = [xml] $ResponseBody
                    Write-Output $BodyObject
                }
                catch {
                    Write-Debug "Failed to convert response body of type '$($ResponseHeaders['content-type'])' to object"
                    Write-Output $ResponseBody
                }
                # Add new line
                Write-Host ""
            }
        }
        else {
            return $Response
        }
    }

}