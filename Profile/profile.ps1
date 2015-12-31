# Set up debugging
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'

$AutomationWorkspace = @{
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

Foreach($_AutomationWorkspace in $AutomationWorkspace.Keys)
{
    $PowerShellModulePath = "$($AutomationWorkspace.$_AutomationWorkspace.Workspace)\$($AutomationWorkspace.$_AutomationWorkspace.ModulePath)"
    $LocalPowerShellModulePath = "$($AutomationWorkspace.$_AutomationWorkspace.Workspace)\$($AutomationWorkspace.$_AutomationWorkspace.LocalPowerShellModulePath)"

    if(Test-Path -Path $PowerShellModulePath) { $env:PSModulePath = "$PowerShellModulePath;$env:PSModulePath" }
    if(Test-Path -Path $LocalPowerShellModulePath) { $env:PSModulePath = "$LocalPowerShellModulePath;$env:PSModulePath" }
}

$Env:LocalAuthoring = $true
$Env:AutomationDefaultWorkspace = 'RunbookExample'
$Env:AutomationWorkspace = $AutomationWorkspace | ConvertTo-Json

# Set up debugging
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'

# Load posh-git example profile
. "$(((Get-Module -Name Posh-Git -ListAvailable).Path -as [System.IO.FileInfo]).Directory)\profile.example.ps1"

Set-StrictMode -Version 1