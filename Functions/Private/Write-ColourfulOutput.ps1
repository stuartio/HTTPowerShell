function Write-ColourfulOutput {
    Param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Output,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $ContentType,

        [Parameter()]
        [string]
        $KeyColour = (Get-PSReadLineOption).CommentColor,

        [Parameter()]
        [string]
        $StringColour = (Get-PSReadLineOption).StringColour,

        [Parameter()]
        [switch]
        $Always
    )

    $Reset = $PSStyle.Reset

    switch -wildcard ($ContentType) {
        'application/*json*' { Write-ColourfulJSON -JSON $Output }
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
                Write-Output "-- Binary data in format '$KeyColour$ContentType$Reset' not shown in terminal --" 
            }
        }
    }
}