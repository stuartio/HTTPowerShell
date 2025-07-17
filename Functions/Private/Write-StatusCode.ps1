function Write-StatusCode {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]
        $RawStatus
    )

    $HTTPVersionFGColour = 'DarkBlue'
    $StatusCodeFGColour = 'DarkBlue'
    $StatusDescriptionFGColour = 'DarkCyan'

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
        Write-Host -ForegroundColor $HTTPVersionFGColour -NoNewline $HTTPPrefix
        Write-Host -ForegroundColor White -NoNewline '/'
        Write-Host -ForegroundColor $HTTPVersionFGColour -NoNewline $HTTPVersion
        Write-Host -ForegroundColor $StatusCodeFGColour -NoNewline " $StatusCode"
        Write-Host -ForegroundColor $StatusDescriptionFGColour " $StatusDescription"
    }
    else {
        throw "Status code '$RawStatus' is in an unknown format"
    }
}