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
        $Output,

        [Parameter(ValueFromPipeline)]
        [string]
        $Body,

        [Parameter(ValueFromRemainingArguments)]
        $AdditionalArgs
    )

    process {
        ### Regexes
        $HeaderParamRegex = '(?<name>[a-zA-Z0-9\-]+):(?<value>.*)'
        $QueryParamRegex = '[a-zA-Z0-9\-]+=(?!=).*'
        $CookieRegex = '[a-zA-Z0-9\-]+==.*'

        ### Defaults
        $HeaderForeGround = 'DarkCyan'
        $DefaultHttpVersion = '1.1'

        $Headers = @{
            'Accept'          = '*/*'
            'Accept-Encoding' = 'gzip,deflate'
            'Connection'      = 'keep-alive'
            'User-Agent'      = 'HttPowershell/0.0.1'
            'Content-Type'    = 'application/json'
        }

        ### Parse Params
        $NamedAdditionalArgs = New-Object -TypeName System.Collections.Generic.List['Hashtable']
        $UnnamedAdditionalArgs = New-Object -TypeName System.Collections.Generic.List['String']
        $AdditionalQueryParams = New-Object -TypeName System.Collections.Generic.List['String']
        $AdditionalRequestCookies = New-Object -TypeName System.Collections.Generic.List['String']
        for ($i = 0; $i -lt $AdditionalArgs.count; $i++) {
            $Arg = $AdditionalArgs[$i]
            if ($Arg.StartsWith('-') -and -not (++$i -gt $AdditionalArgs.count)) {
                $NamedAdditionalArgs.Add(@{
                        $Arg.SubString(1) = $AdditionalArgs[$i]
                    })
            }
            else {
                $UnnamedAdditionalArgs.Add($Arg)
            }
        }

        ### Parse Unnamed args
        foreach ($Arg in $UnnamedAdditionalArgs) {
            if ($Arg -match $HeaderParamRegex) {
                $Headers[$Matches.name] = $Matches.Value
            }
            elseif ($Arg -match $QueryParamRegex) {
                $AdditionalQueryParams.Add($Arg)
            }
            elseif ($Arg -match $CookieRegex) {
                # Add to array but replace == with =
                $AdditionalRequestCookies.Add($Arg.Replace('==', '='))
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
            Headers              = $Headers
            MaximumRedirection   = 0
            SkipHeaderValidation = $true
            SkipHttpErrorCheck   = $true
            Proxy                = $env:https_proxy
            HttpVersion          = $HttpVersion
        }

        ### Parse method
        $DefaultMethods = 'DEFAULT', 'DELETE', 'GET', 'HEAD', 'MERGE', 'OPTIONS', 'PATCH', 'POST', 'PUT', 'TRACE'
        if ($Method -in $DefaultMethods) {
            $IWRParams.Method = $Method
        }
        else {
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                $IWRParams.CustomMethod = $Method
            }
            else {
                Write-Error "Method $Method is not acceptable in Windows Powershell. Please upgrade to version 6+ or use a method from the following table:"
                Write-Error $DefaultMethods.ToString()
            }
        }

        ### ---- Make request
        try {
            $Response = Invoke-WebRequest @IWRParams
        }
        catch {
            Write-Error "Failed to connect to $Uri"
            Write-Error $_
            return
        }

        if ($Output) {
            ### Parse response. Have to use raw as we want to show multiple items for when headers are duplicated
            $RawResponse = $Response.RawContent -split "`r`n"
            $ResponseHeaders = New-Object -TypeName System.Collections.Generic.List['HashTable']
            for ($i = 1; $i -lt $RawResponse.count; $i++) {
                if ($RawResponse[$i] -match $HeaderParamRegex) {
                    $ResponseHeaders.Add(@{
                            name  = $Matches.name
                            value = $Matches.value
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

            if ($Output.contains('H')) {
                Write-Request -Method $Method -HttpVersion $HttpVersion -Uri $Uri
                $Headers.Keys | Sort-Object | ForEach-Object {
                    Write-Host -ForegroundColor $HeaderForeGround -NoNewline $_
                    Write-Host ": $($Headers.$_)"
                }
                # Add new line
                Write-Host ""
            }
            if ($Output.contains('h')) {
                Write-StatusCode $RawResponse[0]
                $ResponseHeaders | Sort-Object -Property Name | ForEach-Object {
                    Write-Host -ForegroundColor $HeaderForeGround -NoNewline $_.Name
                    Write-Host ": $($_.Value)"
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