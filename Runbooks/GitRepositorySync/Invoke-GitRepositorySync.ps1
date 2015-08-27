<#
.Synopsis
    Check GIT repository for new commits. If found sync the changes into
    the current SMA environment

.Parameter RepositoryName
#>
Workflow Invoke-GitRepositorySync
{
    Param(
        [Parameter(Mandatory = $true)]
        [String]
        $RepositoryName
    )
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Prefix 'ContinuousIntegration' `
                                               -Name @(
        'RepositoryInformation',
        'SubscriptionAccessCredentialName',
        'SubscriptionName',
        'AutomationAccountName',
        'RunbookWorkerAccessCredenialName'
    )
                                               
    $SubscriptionAccessCredential = Get-AutomationPSCredential -Name $CIVariables.SubscriptionAccessCredentialName
    $RunbookWorkerAccessCredenial = Get-AutomationPSCredential -Name $CIVariables.RunbookWorkerAccessCredenialName
    Try
    {
        $RepositoryInformation = (ConvertFrom-JSON -InputObject $CIVariables.RepositoryInformation).$RepositoryName
        Sync-GitRepositoryToAzureAutomation -RepositoryInformation $RepositoryInformation `
                                            -AutomationAccountName $CIVariables.AutomationAccountName `
                                            -SubscriptionName $CIVariables.SubscriptionName `
                                            -SubscriptionAccessCredential $SubscriptionAccessCredential `
                                            -RunbookWorkerAccessCredenial $RunbookWorkerAccessCredenial `
                                            -RepositoryName $RepositoryName
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}
