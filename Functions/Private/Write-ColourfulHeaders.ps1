function Write-ColourfulHeaders {
    Param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]
        $Header,

        [Parameter()]
        [string]
        $KeyColour = (Get-PSReadLineOption).CommentColor,

        [Parameter()]
        [string]
        $StringColour = (Get-PSReadLineOption).StringColor
    )

    Process {
        $Reset = $PSStyle.Reset
        Write-Output "$StringColour$($Header.Name)$Reset`: $($Header.Value)"
    }
}