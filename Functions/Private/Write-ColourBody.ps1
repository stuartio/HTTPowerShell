function Write-ColourBody {
    Param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Output,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $ContentType,

        [Parameter(Mandatory)]
        [object]
        $ColourPalette,

        [Parameter()]
        [switch]
        $Always
    )

    switch -wildcard ($ContentType) {
        'application/*json*' { Write-ColourJSON -JSON $Output -ColourPalette $ColourPalette }
        'application/*xml*' { Write-Output $Output } # TODO: Write pretty handler
        'application/*html*' { Write-Output $Output } # TODO: Write pretty handler
        'application/x-mpegURL' { Write-Output $Output } # TODO: Write pretty handler
        'text/*' { Write-Output $Output }
        'multipart/form-data*' { Write-Output $Output }
        '' { Write-Output $Output } # For no content-type, try printing directly
        default {
            if ($Always) {
                Write-Output $Output
            }
            else {
                Write-ColourOutput "-- Binary data in format '|$($ColourPalette.KeyColour)|$ContentType|!|' not shown in terminal --" 
            }
        }
    }
}