function Get-ColourPalette {
    [CmdletBinding()]
    Param (
        [Parameter()]
        [string]
        $KeyColour = (Get-PSReadLineOption).StringColor,

        [Parameter()]
        [string]
        $StringColour = (Get-PSReadLineOption).ListPredictionColor,

        [Parameter()]
        [string]
        $NumberColour = (Get-PSReadLineOption).NumberColor,
        
        [Parameter()]
        [string]
        $CommentColour = (Get-PSReadLineOption).CommentColor,

        [Parameter()]
        [string]
        $OtherColour = (Get-PSReadLineOption).ParameterColor
    )

    $ColourPalette = [PSCustomObject] @{
        KeyColour     = $KeyColour.SubString(2, 2)
        StringColour  = $StringColour.SubString(2, 2)
        NumberColour  = $NumberColour.SubString(2, 2)
        CommentColour = $CommentColour.SubString(2, 2)
        OtherColour   = $OtherColour.SubString(2, 2)
    }

    return $ColourPalette
}