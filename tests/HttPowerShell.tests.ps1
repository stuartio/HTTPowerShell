Describe "Invoke-HTTP Tests" {
    BeforeAll {
        # Import the module or script containing Invoke-HTTP
        Import-Module "$PSScriptRoot\..\httpowershell.psd1" -Force
        $TestHost = "httpbun.com"
        $TestURL = "https://$TestHost"
        # Disable WriteColour colours, as it screws up the validation.
        $env:DISABLE_WC_COLOURS = 1
    }

    Context "Basic Parameter Validation" {
        It "Should throw an error if no Uri is provided" {
            { Invoke-Http -Method GET } | Should -Throw
        }

        It "Should default to GET method if no method is provided" {
            $Result = Invoke-Http $TestURL
            $Result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Alias" -Tag 'Alias' {
        It "should work with the 'web' alias" {
            $Result = web $TestURL
            $Result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Display Options" -Tag 'Display' {
        BeforeAll {
            $DisplayPath = "/status/200"
            $DisplayURL = "$TestURL$DisplayPath"
        }

        It "should show request URI" {
            $Result = Invoke-Http $DisplayURL -Display U
            $Result | Should -BeLike "*$DisplayURL*"
        }

        It "should show request line" {
            $Result = Invoke-Http $DisplayURL -Display R
            $Result | Should -BeLike "GET $DisplayPath*"
        }
        
        It "should show request headers" {
            $Result = Invoke-Http $DisplayURL -Display H
            $Result | Should -Contain "Host: $TestHost"
        }
        
        It "should show the status code with version and description" {
            $Result = Invoke-Http $DisplayURL -Display s
            $Result | Should -Be "HTTP/1.1 200 OK"
        }
        It "should show just the status code" {
            $Result = Invoke-Http $DisplayURL -Display S
            $Result | Should -Be "200"
        }
        It 'should limit request headers' {
            $Result = Invoke-HTTP $DisplayURL -Display H -DisplayHeaders 'host'
            $Result[0] | Should -BeLike "Host: $TestHost*"
            $Result.count | Should -Be 2
        }
        It 'should limit response headers' {
            $Result = Invoke-HTTP $DisplayURL -Display h -DisplayHeaders 'Content-Type', 'date'
            $Result[0] | Should -BeLike 'Content-Type:*'
            $Result[1] | Should -BeLike 'Date:*'
            $Result.count | Should -Be 3
        }
    }

    Context 'Request headers' -Tag 'Headers' {
        BeforeAll {
            $HeaderName1 = 'X-Test-Header'
            $HeaderName2 = 'X-Test-Header2'
            $HeaderValue = 'TestValue'
            $RequestParams = @{
                Uri            = "$TestURL/anything"
                Display        = 'H'
                DisplayHeaders = $HeaderName1
            }
        }
        It 'should send custom request headers using standard IWR format' {
            $Result = Invoke-Http @RequestParams -Headers @{ $HeaderName1 = $HeaderValue }
            $Result[0] | Should -Be "$HeaderName1`: $HeaderValue"
        }
        It 'should send custom request headers using custom format' {
            $Result = Invoke-Http @RequestParams "$HeaderName1`: $HeaderValue"
            $Result[0] | Should -Be "$HeaderName1`: $HeaderValue"
        }
        It 'should send multiple custom request headers using custom format' {
            $Result = Invoke-Http @RequestParams "$HeaderName1`: $HeaderValue" "$HeaderName2`: $HeaderValue" -DisplayHeaders $HeaderName1, $HeaderName2
            $Result[0] | Should -Be "$HeaderName1`: $HeaderValue"
            $Result[1] | Should -Be "$HeaderName2`: $HeaderValue"
        }
    }

    Context 'Request cookies' -Tag 'Cookies' {
        BeforeAll {
            $CookieName1 = 'melove'
            $CookieName2 = 'mealsolove'
            $CookieValue = 'cookiiiiieeeee'
            $RequestParams = @{
                Uri            = "$TestURL/anything"
                Display        = 'H'
                DisplayHeaders = 'cookie'
            }
        }
        It 'should send custom request cookies' {
            $Result = Invoke-Http @RequestParams "$CookieName1`==$CookieValue"
            $Result[0] | Should -Be "cookie: $CookieName1=$CookieValue"
        }
        It 'should send multiple custom request cookies' {
            $Result = Invoke-Http @RequestParams "$CookieName1`==$CookieValue" "$CookieName2`==$CookieValue"
            $Result[0] | Should -Be "cookie: $CookieName1=$CookieValue;$CookieName2=$CookieValue"
        }
    }

    Context 'Request queryparams' -Tag 'QueryParams' {
        BeforeAll {
            $QueryParamName1 = 'question'
            $QueryParamName2 = 'anotherquestion'
            $QueryParamValue1 = 'who are you'
            $EncodedQueryParamValue1 = [System.Web.HttpUtility]::UrlEncode($QueryParamValue1)
            $QueryParamValue2 = 'what do you want'
            $EncodedQueryParamValue2 = [System.Web.HttpUtility]::UrlEncode($QueryParamValue2)
            $RequestParams = @{
                Uri            = "$TestURL/anything"
                Display        = 'U'
                DisplayHeaders = 'cookie'
            }
        }
        It 'should send custom request queryparams' {
            $Result = Invoke-Http @RequestParams "$QueryParamName1`=$QueryParamValue1"
            $Result | Should -Be "$TestURL/anything?$QueryParamName1=$EncodedQueryParamValue1"
        }
        It 'should send multiple custom request queryparams' {
            $Result = Invoke-Http @RequestParams "$QueryParamName1`=$QueryParamValue1" "$QueryParamName2`=$QueryParamValue2"
            $Result | Should -Be "$TestURL/anything?$QueryParamName1=$EncodedQueryParamValue1&$QueryParamName2=$EncodedQueryParamValue2"
        }
    }

    Context 'Combine headers, queries & cookies' -Tag 'Combo' {
        BeforeAll {
            $HeaderName = 'X-Test-Header'
            $HeaderValue = 'TestValue'
            $CookieName = 'melove'
            $CookieValue = 'cookiiiiieeeee'
            $QueryParamName = 'question'
            $QueryParamValue = 'who are you'
            $EncodedQueryParamValue = [System.Web.HttpUtility]::UrlEncode($QueryParamValue)
            $RequestParams = @{
                Uri            = "$TestURL/anything"
                Display        = 'UH'
                DisplayHeaders = 'cookie', $HeaderName
            }
        }
        It 'should send custom request headers, cookies and queryparams' {
            $Result = Invoke-Http @RequestParams "$HeaderName`: $HeaderValue" "$CookieName`==$CookieValue" "$QueryParamName`=$QueryParamValue"
            $Result[0] | Should -Be "$TestURL/anything?$QueryParamName=$EncodedQueryParamValue"
            $Result[1] | Should -Be "cookie: $CookieName=$CookieValue"
            $Result[2] | Should -Be "$HeaderName`: $HeaderValue"
        }
    }

    Context "HTTP Method Validation" -Tag 'Method' {
        It "Should accept standard HTTP methods" -ForEach @("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD", "TRACE") {
            $Result = Invoke-Http -Uri "$TestURL/any" -Method $_ -Display S
            $Result | Should -Be 200
        }

        It "Should complete, even for an unsupported HTTP methods" {
            Invoke-Http -Uri "https://example.com" -Method "INVALID"
        }
    }

    Context "Authentication Parameter Validation" -Tag 'Authentication' {
        Context 'Basic' -Tag 'Basic' {
            It "Should handle Basic authentication" {
                $Path = "/basic-auth/user/passwd"
                $Credentials = New-Object System.Management.Automation.PSCredential ("user", (ConvertTo-SecureString "passwd" -AsPlainText -Force))
                $Result = Invoke-Http -Uri "$TestURL$Path" -Authentication Basic -Credential $Credentials -Display S
                $Result | Should -Be 200
            }
            It "Should fail Basic authentication with invalid creds" {
                $Path = "/basic-auth/user/passwd"
                $Credentials = New-Object System.Management.Automation.PSCredential ("user", (ConvertTo-SecureString "wrongpasswd" -AsPlainText -Force))
                $Result = Invoke-Http -Uri "$TestURL$Path" -Authentication Basic -Credential $Credentials -Display S
                $Result | Should -Be 401
            }
        }
        Context 'EdgeGrid' -Tag 'EdgeGrid' {
            BeforeAll {
                $EdgeGridHost1 = 'akab-h05tnam3wl42son7nktnlnnx-11111111.luna.akamaiapis.net'
                $EdgeGridHost2 = 'akab-h05tnam3wl42son7nktnlnnx-22222222.luna.akamaiapis.net'
                $EdgeGridAccessToken = 'akab-acc35t0k3nodujqunph3w7hzp7-gtm6ij'
                $EdgeGridClientToken = 'akab-c113ntt0k3n4qtari252bfxxbsl-yvsdj'
                $EdgeGridClientSecret = 'C113nt53KR3TN6N90yVuAgICxIRwsObLi0E67/N8eRN='

                $TestEdgeRCFile = 'TestDrive:/.edgerc'
                $TestSection1 = 'default'
                $TestSection2 = 'pester'
                $ExportParams = @{
                    HostName     = $EdgeGridHost1
                    AccessToken  = $EdgeGridAccessToken
                    ClientToken  = $EdgeGridClientToken
                    ClientSecret = $EdgeGridClientSecret
                    EdgeRCFile   = $TestEdgeRCFile
                }
                Export-EdgegridCredentials @ExportParams -Section $TestSection1
                Export-EdgegridCredentials @ExportParams -Section $TestSection2 -HostName $EdgeGridHost2
            }
            Context 'Real' {
                It "Should handle EdgeGrid authentication from the default (real) .edgerc file" {
                    if ((Test-Path ~/.edgerc)) {
                        $Result = Invoke-Http -Uri '/papi/v1/contracts' -Authentication EdgeGrid -Display S
                        $Result | Should -Be 200
                    }
                    else {
                        Write-Warning "No .edgerc file found in home directory. Skipping test."
                    }
                }
            }
            Context 'Mocked' {
                BeforeAll {
                    $TestParams = @{
                        Uri            = '/papi/v1/contracts'
                        Authentication = 'EdgeGrid'
                        EdgeRCFile     = $TestEdgeRCFile
                        Display        = 'U'
                    }
                    Mock 'Invoke-WebRequest' {
                        return @{
                            StatusCode = 200
                            Content    = 'Mocked Response'
                        }
                    }
                }
                It "Should read credenials from a custom .edgerc file" {
                    $Result = Invoke-Http @TestParams
                    $Result | Should -BeLike "*https://$EdgeGridHost1/papi/v1/contracts*"
                }
                It "Should read credenials from a custom .edgerc file and section" {
                    $Result = Invoke-Http @TestParams -Section $TestSection2
                    $Result | Should -BeLike "*https://$EdgeGridHost2/papi/v1/contracts*"
                }
            }
        }

        Context 'Client Certs' -Tag 'mtls' {
            BeforeAll {
                $ClientCertPath = "$PSScriptRoot\data\badssl.com-client.pem"
                $ClientKeyPath = "$PSScriptRoot\data\badssl.com-client.key"
                $ClienEKeyPath = "$PSScriptRoot\data\badssl.com-client.ekey"
                $ClientCert = Get-Content -Raw -Path $ClientCertPath
                $ClientKey = Get-Content -Raw -Path $ClientKeyPath
                $ClientEKey = Get-Content -Raw -Path $ClienEKeyPath
            }
            It 'succeeds when reading non-encrypted data from files' {
                $TestParams = @{
                    Uri                   = 'https://client.badssl.com/'
                    ClientCertificateFile = $ClientCertPath
                    ClientKeyFile         = $ClientKeyPath
                    Display               = 'S'
                }
                $Result = Invoke-Http @TestParams
                $Result | Should -Be 200
            }
            It 'succeeds when reading non-encrypted data from variables' {
                $TestParams = @{
                    Uri               = 'https://client.badssl.com/'
                    ClientCertificate = $ClientCert
                    ClientKey         = $ClientKey
                    Display           = 'S'
                }
                $Result = Invoke-Http @TestParams
                $Result | Should -Be 200
            }
            It 'succeeds when reading data from a mixture of files and variables' {
                $TestParams = @{
                    Uri                   = 'https://client.badssl.com/'
                    ClientCertificateFile = $ClientCertPath
                    ClientKey             = $ClientKey
                    Display               = 'S'
                }
                $Result = Invoke-Http @TestParams
                $Result | Should -Be 200
            }
            It 'succeeds when using an encrypted key from a file, with a password provided' {
                $TestParams = @{
                    Uri                   = 'https://client.badssl.com/'
                    ClientCertificateFile = $ClientCertPath
                    ClientKeyFile         = $ClienEKeyPath
                    ClientKeyPassword     = 'badssl.com'
                    Display               = 'S'
                }
                $Result = Invoke-Http @TestParams
                $Result | Should -Be 200
            }
            It 'succeeds when using an encrypted key from a variable, with a password provided' {
                $TestParams = @{
                    Uri                   = 'https://client.badssl.com/'
                    ClientCertificateFile = $ClientCertPath
                    ClientKey             = $ClientEKey
                    ClientKeyPassword     = 'badssl.com'
                    Display               = 'S'
                }
                $Result = Invoke-Http @TestParams
                $Result | Should -Be 200
            }
        }
    }

    Context 'HTTP Versions' -Tag 'HttpVersion' {
        BeforeAll {
            $TestParams = @{
                Uri     = "$TestURL/status/200"
                Display = 's'
            }
        }
        It 'shows HTTP 1.0 was used when specified' {
            $Result = Invoke-Http @TestParams -Http1
            $Result | Should -Be 'HTTP/1.0 200 OK'
        }
        It 'shows HTTP 1.1 was used when specified' {
            $Result = Invoke-Http @TestParams -Http11
            $Result | Should -Be 'HTTP/1.1 200 OK'
        }
        It 'shows HTTP 2.0 was used when specified' {
            $Result = Invoke-Http @TestParams -Http2
            $Result | Should -Be 'HTTP/2.0 200 OK'
        }
        # TODO: figure out how to get h3 tested. Might need a special test site
        # It 'shows HTTP 3.0 was used when specified' {
        #     $Result = Invoke-Http @TestParams -Http3
        #     $Result | Should -Be 'HTTP/3.0 200 OK'
        # }
        It 'defaults to HTTP 1.1 when not specified' {
            $Result = Invoke-Http @TestParams
            $Result | Should -Be 'HTTP/1.1 200 OK'
        }
        It 'accepts HTTP 1.0 when specified as a string' {
            $Result = Invoke-Http @TestParams -HttpVersion '1.0'
            $Result | Should -Be 'HTTP/1.0 200 OK'
        }
        It 'accepts HTTP 1.1 when specified as a string' {
            $Result = Invoke-Http @TestParams -HttpVersion '1.1'
            $Result | Should -Be 'HTTP/1.1 200 OK'
        }
        It 'accepts HTTP 2.0 when specified as a string' {
            $Result = Invoke-Http @TestParams -HttpVersion '2.0'
            $Result | Should -Be 'HTTP/2.0 200 OK'
        }
        # It 'accepts HTTP 3.0 when specified as a string' {
        #     $Result = Invoke-Http @TestParams -HttpVersion '3.0'
        #     $Result | Should -Be 'HTTP/3.0 200 OK'
        # }
    }

    Context 'Resolve' -Tag 'Resolve' {
        It 'resolves to the same hostname' {
            $TestParams = @{
                Uri     = $TestURL
                Resolve = $TestHost
                Display = 'S'
            }
            $Result = Invoke-Http @TestParams
            $Result | Should -Be 200

        }
        It 'fails when resolving to a mismatched hostname' {
            $TestParams = @{
                Uri         = $TestURL
                Resolve     = 'bananas.com'
                Display     = 'S'
                ErrorAction = 'Stop'
            }
            { Invoke-Http @TestParams -ErrorAction Stop } | Should -Throw
        }
        It 'does not fail when resolving to a mismatched hostname with -SkipCertificateCheck' {
            $TestParams = @{
                Uri                  = $TestURL
                Resolve              = 'bananas.com'
                Display              = 'S'
                ErrorAction          = 'Stop'
                SkipCertificateCheck = $true
            }
            Invoke-Http @TestParams -ErrorAction Stop
        }
        It 'resolves to Akamai Staging' {
            $TestParams = @{
                Uri            = 'https://www.akamai.com/'
                Resolve        = 'AkamaiStaging'
                Display        = 'h'
                DisplayHeaders = 'X-Akamai-Staging'
            }
            $Result = Invoke-Http @TestParams
            $Result[0] | Should -BeLike "X-Akamai-Staging: ESSL*"
        }
    }

    AfterAll {
        $env:DISABLE_WC_COLOURS = $null
    }
}