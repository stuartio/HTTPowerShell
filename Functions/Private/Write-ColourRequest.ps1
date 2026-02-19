function Write-ColourRequest {
    Param(
        [Parameter(Mandatory)]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [string]
        $HttpVersion,

        [Parameter(Mandatory)]
        [System.Uri]
        $ParsedUri,

        [Parameter(Mandatory)]
        [object]
        $ColourPalette
    )

    Write-ColourOutput "|-$($ColourPalette.CommentColour)-|$($Method.ToUpper())|-!-| $($ParsedUri.PathAndQuery) |-$($ColourPalette.CommentColour)-|HTTP|-!-|/|-$($ColourPalette.CommentColour)-|$HttpVersion|-!-|"
}