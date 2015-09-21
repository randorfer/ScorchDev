# SMA setup

## Modules
$env:AutomationWorkspace = 'C:\GIT\ScorchDev'
$env:SMAModulePath = "$env:AutomationWorkspace\PowerShellModules"
$env:SMARunbookPath = "$env:AutomationWorkspace\Runbooks"
$env:PSModulePath = "$env:SMAModulePath;$env:AutomationWorkspace\LocalPowerShellModules;$env:PSModulePath"
$env:AutomationWebServiceEndpoint = 'https://scorchsma01.scorchdev.com'
$env:LocalAuthoring = $true
$env:LocalSMAVariableUpdateInterval = 0
# Set up debugging
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'

# Load posh-git example profile
. "$env:SMAModulePath\posh-git\profile.example.ps1"

Set-StrictMode -Version 1
