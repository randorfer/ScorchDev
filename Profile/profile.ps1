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

if((Get-Module -Name posh-git -ListAvailable) -as [bool])
{
    # use this instead (see about_Modules for more information):
    Import-Module posh-git


    # Set up a simple prompt, adding the git prompt parts inside git repos
    function global:prompt {
        $realLASTEXITCODE = $LASTEXITCODE

        Write-Host($pwd.ProviderPath) -nonewline

        Write-VcsStatus

        $global:LASTEXITCODE = $realLASTEXITCODE
        return "> "
    }
}

Set-StrictMode -Version Latest