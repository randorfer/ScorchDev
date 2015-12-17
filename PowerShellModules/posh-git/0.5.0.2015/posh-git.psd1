@{
ModuleToProcess = 'posh-git.psm1'
ModuleVersion = '0.5.0.2015'
GUID = '405c2105-800b-427d-8066-996df0053caf'
Author = 'Team'
CompanyName = 'Posh'
Copyright = 'Copyright (c) 2015 MIT.'
Description = 'PoSh Git'
PowerShellVersion = '3.0'
FunctionsToExport = @( 
        'Invoke-NullCoalescing',
        'Write-GitStatus',
        'Write-Prompt',
        'Get-GitStatus',
        'Get-GitDirectory',
        'TabExpansion',
        'Get-AliasPattern',
        'Update-AllBranches',
        'tgit'
)
# CmdletsToExport = '*'
# VariablesToExport = @()
# AliasesToExport = '*'
}
