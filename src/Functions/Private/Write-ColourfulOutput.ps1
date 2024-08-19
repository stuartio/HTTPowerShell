function Write-ColourfulOutput {
    Param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Output,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $ContentType
    )

    switch -wildcard ($ContentType) {
        'application/json*' { Write-ColourfulJSON -JSON $Output }
        default { Write-Host $Output }
    }
}