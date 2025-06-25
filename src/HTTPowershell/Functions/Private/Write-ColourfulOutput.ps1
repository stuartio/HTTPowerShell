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
        $KeyColor = (Get-PSReadLineOption).CommentColor,

        [Parameter()]
        [string]
        $StringColor = (Get-PSReadLineOption).StringColor
    )

    $Reset = $PSStyle.Reset

    switch -wildcard ($ContentType) {
        'application/*json*' { Write-ColourfulJSON -JSON $Output }
        'application/*xml*' { Write-Host $Output } # TODO: Write pretty handler
        'application/*html*' { Write-Host $Output } # TODO: Write pretty handler
        'application/x-mpegURL' { Write-Host $Output } # TODO: Write pretty handler
        'text/*' { Write-Host $Output }
        'multipart/form-data*' { Write-Host $Output }
        '' { Write-Host $Output } # For no content-type, try printing directly
        default { 
            Write-Host "-- Binary data in format '$KeyColor$ContentType$Reset' not shown in terminal --" 
        }
    }
}