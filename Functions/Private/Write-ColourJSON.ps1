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