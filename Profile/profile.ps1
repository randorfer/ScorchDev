# SMA setup

## Modules
$env:AutomationWorkspace = 'C:\GIT\ScorchDev'
$env:SMAModulePath = "$env:AutomationWorkspace\PowerShellModules"
$env:SMAGlobalsPath = "$env:AutomationWorkspace\Globals"
$env:PSModulePath = "$env:SMAModulePath;$env:AutomationWorkspace\LocalPowerShellModules;$env:PSModulePath"
$env:LocalAuthoring = $true

# Set up debugging
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'

# Load posh-git example profile
. "$env:SMAModulePath\posh-git\profile.example.ps1"

Set-StrictMode -Version 1