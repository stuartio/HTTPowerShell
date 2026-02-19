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