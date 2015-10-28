## Modules
$Global:AutomationWorkspace = @{
    'SCOrchDev' = @{
        'Workspace' = 'C:\GIT\SCOrchDev'
        'ModulePath' = 'PowerShellModules'
        'GlobalPath' = 'Globals'
        'LocalPowerShellModulePath' = 'LocalPowerShellModules'
        'RunbookPath' = 'Runbooks'
    }
    'RunbookExample' = @{
        'Workspace' = 'C:\GIT\RunbookExample'
        'ModulePath' = 'PowerShellModules'
        'GlobalPath' = 'Globals'
        'LocalPowerShellModulePath' = 'LocalPowerShellModules'
        'RunbookPath' = 'Runbooks'
    }
}
Foreach($_AutomationWorkspace in $Global:AutomationWorkspace.Keys)
{
    
    $PowerShellModulePath = "$($Global:AutomationWorkspace.$_AutomationWorkspace.Workspace)\$($Global:AutomationWorkspace.$_AutomationWorkspace.ModulePath)"
    $LocalPowerShellModulePath = "$($Global:AutomationWorkspace.$_AutomationWorkspace.Workspace)\$($Global:AutomationWorkspace.$_AutomationWorkspace.LocalPowerShellModulePath)"

    if(Test-Path -Path $PowerShellModulePath) { $env:PSModulePath = "$PowerShellModulePath;$env:PSModulePath" }
    if(Test-Path -Path $LocalPowerShellModulePath) { $env:PSModulePath = "$LocalPowerShellModulePath;$env:PSModulePath" }
}

$env:LocalAuthoring = $true
$Global:AutomationDefaultWorkspace = 'RunbookExample'

# Set up debugging
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'

# Load posh-git example profile
. "$(((Get-Module -Name Posh-Git -ListAvailable).Path -as [System.IO.FileInfo]).Directory)\profile.example.ps1"

Set-StrictMode -Version 1