function Write-StatusCode {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]
        $RawStatus,

        [Parameter()]
        [string]
        $HTTPVersionFGColour = (Get-PSReadLineOption).CommentColor,

        [Parameter()]
        [string]
        $StatusCodeFGColour = (Get-PSReadLineOption).StringColour,

        [Parameter()]
        [string]
        $StatusDescriptionFGColour = (Get-PSReadLineOption).StringColor,

        [Parameter()]
        [string]
        $OtherColour = (Get-PSReadLineOption).ParameterColor
    )

    $Reset = $PSStyle.Reset
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

        Write-Output "$HTTPVersionFGColour$HTTPPrefix$Reset/$HTTPVersionFGColour$HTTPVersion $StatusCodeFGColour$StatusCode$Reset $StatusDescription"
    }
    else {
        throw "Status code '$RawStatus' is in an unknown format"
    }
}