function Get-ColourPalette {
    [CmdletBinding()]
    Param (
        [Parameter()]
        [string]
        $KeyColour = (Get-PSReadLineOption).StringColor,

        [Parameter()]
        [string]
        $StringColour = (Get-PSReadLineOption).TypeColor,

        [Parameter()]
        [string]
        $NumberColour = (Get-PSReadLineOption).ListPredictionColor,

        [Parameter()]
        [string]
        $OtherColour = (Get-PSReadLineOption).ParameterColor
    )

    $ColourPalette = [PSCustomObject] @{
        KeyColour    = Convert-ANSIColour $KeyColour
        StringColour = Convert-ANSIColour $StringColour
        NumberColour = Convert-ANSIColour $NumberColour
        OtherColour  = Convert-ANSIColour $OtherColour
    }

    return $ColourPalette
}