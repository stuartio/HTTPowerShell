function Convert-ANSIColour {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]
        $ColourSequence
    )

    $Colours = @{
        '30' = 'Black'
        '31' = 'DarkRed'
        '32' = 'DarkGreen'
        '33' = 'DarkYellow'
        '34' = 'DarkBlue'
        '35' = 'DarkMagenta'
        '36' = 'DarkCyan'
        '37' = 'White'
        '90' = 'Black'
        '91' = 'Red'
        '92' = 'Green'
        '93' = 'Yellow'
        '94' = 'Blue'
        '95' = 'Magenta'
        '96' = 'Cyan'
        '97' = 'White'
    }

    if ($ColourSequence -match '\[([0-9]{2})m') {
        $ColourCode = $Matches[1]
        if ($Colours.ContainsKey($ColourCode)) {
            return $Colours[$ColourCode]
        }
    }

    return $ColourSequence
}