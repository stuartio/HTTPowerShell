function Write-ColourfulJSON {
    Param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $JSON,

        [Parameter()]
        [string]
        $KeyColor = (Get-PSReadLineOption).CommentColor,

        [Parameter()]
        [string]
        $StringColor = (Get-PSReadLineOption).StringColor,

        [Parameter()]
        [string]
        $NumberColor = (Get-PSReadLineOption).ListPredictionColor,

        [Parameter()]
        [string]
        $OtherColor = (Get-PSReadLineOption).ParameterColor
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
        $Reset = $PSStyle.Reset

        # Format JSON
        $FormattedJSON = ConvertFrom-Json -InputObject $JSON | ConvertTo-Json -Depth 100

        # Find keys as any line which starts with a double-quoted string followed by a colon
        $FormattedJSON = $FormattedJSON -Replace '(?m)([ ]+)("[^"\\\n\r]*(?:\\.[^"\\]*)*"(?=:))', "`$1$KeyColor`$2$Reset"

        # Find all other sets of characters that the same match but NOT followed by a colon
        $FormattedJSON = $FormattedJSON -replace '(?m)([ ]+)("[^"\\\n\r]*(?:\\.[^"\\]*)*"(?!:))', "`$1$StringColor`$2$Reset"

        #Find true/false/null strings that end a line and colorize
        $FormattedJSON = $FormattedJSON -replace "(?m)(true|false|null)$EOL", "$OtherColor`$1$Reset"

        # Find numbers that end a line and colorize
        $FormattedJSON = $FormattedJSON -replace "(?m)(:[ ]*)(-?[\d\.]+([eE]{1}[+-][\d]+)?)$EOL", "`$1$NumberColor`$2$Reset"

        Write-Host $FormattedJSON
    }
}