<#
.SYNOPSIS
Build the module
.DESCRIPTION
Polls functions directory and builds out the necessary module manifest params
.PARAMETER Version
Module version
#>
param(
    [Parameter()]
    $Version
)

$ModuleDirectory = "$PSScriptRoot/../"
$ModuleName = (Get-Item "$PSScriptRoot/../").Name

# Clear previously loaded modules.
if ( (Get-Module $ModuleName) ) {
    Remove-Module $ModuleName
}

Write-Host -ForegroundColor Cyan "Building module $ModuleName"
    
$ModuleFile = Get-ChildItem $ModuleDirectory/*.psm1
$DataFile = Get-ChildItem $ModuleDirectory/*.psd1
$PrivateFiles = Get-ChildItem -Path $PSScriptRoot/../Functions/Private -Recurse -Filter *.ps1
$PublicFiles = Get-ChildItem -Path $PSScriptRoot/../Functions/Public -Recurse -Filter *.ps1
$Aliases = New-Object -TypeName System.Collections.ArrayList

# Collate all funtions into one file
$PSM1Content = ''
$PrivateFiles | ForEach-Object {
    $PSM1Content += Get-Content -Raw $_.FullName
    $PSM1Content += "`n"
}
$PublicFiles | ForEach-Object {
    $PSM1Content += Get-Content -Raw $_.FullName
    $PSM1Content += "`n"
}
# Write psm1 content to new file
$PSM1Content | Set-Content -Path $ModuleFile -NoNewline -Force -Encoding UTF8

# Dot source the module file to get aliases
Get-Content -Raw $ModuleFile | Invoke-Expression
    
foreach ($File in $PublicFiles) {
    try {
        $Alias = Get-Alias -Definition $File.baseName -ErrorAction Stop
        if ($Alias) {
            $Aliases.Add($Alias.Name) | Out-Null
        }
    }
    catch {
    
    }
}
    
$Params = @{
    Path              = $DataFile
    FunctionsToExport = $PublicFiles.BaseName
    AliasesToExport   = $Aliases
    CmdletsToExport   = @()
    Copyright         = '(c) 2026 Stuart Macleod. All rights reserved.'
    Author            = 'Stuart Macleod'
    RequiredModules   = @(
        @{ModuleName = 'WriteColour'; GUID = '704cd14a-5f5e-46ae-887e-70dd29378136'; ModuleVersion = '0.7.0'; }
    )
}
    
if ($Version) {
    $Params.ModuleVersion = $Version
}
    
Update-ModuleManifest @Params


# Finally remove all modules to force reload of new data from saved file
$ModuleLoaded = Get-Module $ModuleName
if ($ModuleLoaded) {
    Remove-Module $ModuleName
}

Import-Module $ModuleFile -Force
Write-Host -ForegroundColor Green 'Process complete'

