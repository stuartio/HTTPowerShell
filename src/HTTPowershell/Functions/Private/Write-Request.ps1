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
    $HTTPVersionFGColour = 'DarkBlue'
    $PathFGColour = 'DarkCyan'

    Write-Host -ForegroundColor $MethodFGColour -NoNewline $Method
    Write-Host -ForegroundColor $PathFGColour -NoNewline " $($ParsedUri.PathAndQuery)"
    Write-Host -ForegroundColor $HTTPVersionFGColour -NoNewline " HTTP"
    Write-Host -ForegroundColor White -NoNewline "/"
    Write-Host -ForegroundColor $HTTPVersionFGColour $HttpVersion
}