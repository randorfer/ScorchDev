# SMA setup

## Modules
$env:AutomationWorkspace = 'C:\GIT\ScorchDev'
$env:SMAModulePath = "$env:AutomationWorkspace\PowerShellModules"
$env:SMARunbookPath = "$env:AutomationWorkspace\SMA"
$env:PSModulePath = "$env:SMAModulePath;$env:AutomationWorkspace\LocalPowerShellModules;$env:PSModulePath"
$env:AutomationWebServiceEndpoint = 'https://mgoapsmad1'
$env:LocalAuthoring = $true
$env:LocalSMAVariableUpdateInterval = 0
# Set up debugging
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'

# Load posh-git example profile
. "$env:SMAModulePath\posh-git\profile.example.ps1"

Set-StrictMode -Version 1