function Write-Request {
    Param(
        [Parameter(Mandatory)]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [string]
        $HttpVersion,

        [Parameter(Mandatory)]
        [string]
        $Uri
    )

    $MethodFGColour = 'Green'
    $HTTPVersionFGColour = 'DarkBlue'
    $PathFGColour = 'DarkCyan'

    Write-Debug "Uri = $uri"

    # Split uri
    $UriComponents = [System.Uri]::new($Uri)

    Write-Host -ForegroundColor $MethodFGColour -NoNewline $Method
    Write-Host -ForegroundColor $PathFGColour -NoNewline " $($UriComponents.PathAndQuery)"
    Write-Host -ForegroundColor $HTTPVersionFGColour -NoNewline " HTTP"
    Write-Host -ForegroundColor White -NoNewline "/"
    Write-Host -ForegroundColor $HTTPVersionFGColour $HttpVersion
}