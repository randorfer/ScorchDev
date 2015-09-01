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
    
    $AutomationAccountName = Get-AutomationVariable -Name 'Global-AutomationAccountName'
    $SubscriptionName = Get-AutomationVariable -Name 'Global-SubscriptionName'
    $SubscriptionAccessCredentialName = Get-AutomationVariable -Name 'Global-SubscriptionAccessCredentialName'
    $SubscriptionAccessCredential = Get-AutomationPSCredential -Name $SubscriptionAccessCredentialName

    $CIVariables = Get-BatchAutomationVariable -Prefix 'ContinuousIntegration' `
                                               -AutomationAccountName $AutomationAccountName `
                                               -SubscriptionName $SubscriptionName `
                                               -Credential $SubscriptionAccessCredential `
                                               -Name @(
        'RepositoryInformation',
        'RunbookWorkerAccessCredentialName'
    )
                                               
    $RunbookWorkerAccessCredential = Get-AutomationPSCredential -Name $CIVariables.RunbookWorkerAccessCredentialName
    Try
    {
        $RepositoryInformation = (ConvertFrom-JSON -InputObject $CIVariables.RepositoryInformation).$RepositoryName
        Sync-GitRepositoryToAzureAutomation -RepositoryInformation $RepositoryInformation `
                                            -AutomationAccountName $AutomationAccountName `
                                            -SubscriptionName $SubscriptionName `
                                            -SubscriptionAccessCredential $SubscriptionAccessCredential `
                                            -RunbookWorkerAccessCredenial $RunbookWorkerAccessCredential `
                                            -RepositoryName $RepositoryName `
                                            -RepositoryInformationJSON $CIVariables.RepositoryInformation
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}
