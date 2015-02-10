<#
    .Synopsis
        Check GIT repository for new commits. If found sync the changes into
        the current SMA environment

    .Parameter Path
        The path to the root of the Git Repository

    .Parameter Branch
        The branch of the repository to syncronize this SMA environment with

    .Parameter RunbookFolder
        The relative path from the repository root that will contain all all
        runbook files

    .Parameter PowerShellModuleFolder
        The relative path from the repository root that will contain all all
        PowerShell module folders
#>
Workflow Invoke-GitRepositorySync
{
    Param([Parameter(Mandatory=$true)][String] $Path,
          [Parameter(Mandatory=$true)][String] $Branch)
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('RepositoryInformation') `
                                               -Prefix 'SMAContinuousIntegration'

    Try
    {
        $RepositoryInformation = (ConvertFrom-Json $CIVariables.RepositoryInformation)."$Path"
        Write-Verbose -Message "`$RepositoryInformation [$(ConvertTo-JSON $RepositoryInformation)]"

        $RepoChangeJSON = Find-GitRepoChange -Path $Path `
                                             -Branch $Branch `
                                             -LastCommit $RepositoryInformation.CurrentCommit."$Branch"
        $RepoChange = ConvertFrom-JSON -InputObject $RepoChangeJSON
    }
    Catch
    {

    }

    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}