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

    Context "Alias" {
        It "should work with the 'web' alias" {
            $Result = web $TestURL
            $Result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Display Options" {
        BeforeAll {
            $DisplayPath = "/status/200"
            $DisplayURL = "$TestURL$DisplayPath"
        }

        It "should show request line" {
            $Result = Invoke-Http $DisplayURL -Display H
            $Result[0] | Should -BeLike "GET $DiplayPath*"
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
    }

    Context "HTTP Method Validation" {
        It "Should accept standard HTTP methods" -ForEach @("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD", "TRACE") {
            $Result = Invoke-Http -Uri "$TestURL/any" -Method $_ -Display S
            $Result | Should -Be 200
        }

        It "Should complete, even for an unsupported HTTP methods" {
            Invoke-Http -Uri "https://example.com" -Method "INVALID"
        }
    }

    # Context "Authentication Parameter Validation" {
    #     It "Should handle EdgeGrid authentication" {
    #         $MockUri = "https://example.com"
    #         Mock -CommandName Get-AkamaiCredentials -MockWith {
    #             @{
    #                 host             = "example.com"
    #                 AccountSwitchKey = "test-key"
    #             }
    #         }

    #         Mock -CommandName Get-AkamaiAuthHeader -MockWith {
    #             "AuthorizationHeader"
    #         }

    #         $Result = Invoke-Http -Uri $MockUri -Authentication EdgeGrid
    #         $Result | Should -Not -BeNullOrEmpty
    #     }
    # }

    AfterAll {
        $env:DISABLE_WC_COLOURS = $null
    }
}