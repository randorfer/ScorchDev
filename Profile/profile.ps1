# SMA setup

## Modules
$env:AutomationWorkspace = 'C:\GIT\ScorchDev'
$env:AutomationModulePath = "$env:AutomationWorkspace\PowerShellModules"
$env:AutomationGlobalsPath = "$env:AutomationWorkspace\Globals"
$env:AutomationWorkflowPath = "$env:AutomationWorkspace\Runbooks"
$env:PSModulePath = "$env:AutomationModulePath;$env:AutomationWorkspace\LocalPowerShellModules;$env:PSModulePath"
$env:LocalAuthoring = $true

# Set up debugging
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'

# Load posh-git example profile
. "$env:AutomationModulePath\posh-git\profile.example.ps1"

Set-StrictMode -Version 1