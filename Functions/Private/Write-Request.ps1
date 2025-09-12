function Write-Request {
    Param(
        [Parameter(Mandatory)]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [string]
        $HttpVersion,

        [Parameter(Mandatory)]
        [System.Uri]
        $ParsedUri
    )

    $MethodFGColour = 'Green'
    $HTTPVersionFGColour = 'Green'
    $PathFGColour = 'DarkCyan'

    Write-ColourOutput "|$MethodFGColour|$Method|!| |$PathFGColour|$($ParsedUri.PathAndQuery)|!| |$HTTPVersionFGColour|HTTP|!|/|$HTTPVersionFGColour|$HttpVersion|!|"
}