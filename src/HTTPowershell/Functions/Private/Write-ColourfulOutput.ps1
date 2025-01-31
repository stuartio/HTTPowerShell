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
        'application/*json*' { Write-ColourfulJSON -JSON $Output }
        'application/*xml*' { Write-Host $Output }
        'application/*html*' { Write-Host $Output }
        'text/*' { Write-Host $Output }
        default { Write-Host "-- Binary data in format '$ContentType' not shown in termainal --" }
    }
}