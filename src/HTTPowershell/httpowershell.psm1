$ItemSplat = @{
    Filter      = '*.ps1'
    Recurse     = $true
    ErrorAction = 'Stop'
    Path        = "$PSScriptRoot/Functions"
}
try {
    $Functions = Get-ChildItem @ItemSplat
}
catch {
    Write-Error $_
    throw "Unable to get get file information from Public & Private src."
}

# dot source all .ps1 file(s) found
foreach ($Function in $Functions) {
    try {
        . $Function.FullName
    }
    catch {
        throw "Unable to dot source [$($Function.FullName)]"

    }
}