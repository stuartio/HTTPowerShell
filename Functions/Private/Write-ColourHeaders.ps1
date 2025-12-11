function Write-ColourHeaders {
    Param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]
        $Header,

        [Parameter(Mandatory)]
        [object]
        $ColourPalette
    )

    Process {
        Write-ColourOutput "|$($ColourPalette.KeyColour)|$($Header.Name)|!|: $($Header.Value)"
    }
}