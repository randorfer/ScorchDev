<#
.Synopsis
    Check GIT repository for new commits. If found sync the changes into
    the current SMA environment

.Parameter RepositoryName
#>
Workflow Monitor-GitRepositoryChange
{
    Param(
    )
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    
    $AutomationAccountName = Get-AutomationVariable -Name 'Global-AutomationAccountName'
    $SubscriptionName = Get-AutomationVariable -Name 'Global-SubscriptionName'
    $SubscriptionAccessCredentialName = Get-AutomationVariable -Name 'Global-SubscriptionAccessCredentialName'
    $RunbookWorkerAccessCredentialName = Get-AutomationVariable -Name 'ContinuousIntegration-RunbookWorkerAccessCredentialName'
    $RepositoryName = Get-AutomationVariable -Name 'ContinuousIntegration-RepositoryName'
    do
    {
        $NextRun = (Get-Date).AddMinutes(1)
        
        $RepositoryInformationJSON = Get-AutomationVariable -Name 'ContinuousIntegration-RepositoryInformation'
        $SubscriptionAccessCredential = Get-AutomationPSCredential -Name $SubscriptionAccessCredentialName
        $RunbookWorkerAccessCredential = Get-AutomationPSCredential -Name $RunbookWorkerAccessCredentialName
        Try
        {
            $RepositoryInformation = (ConvertFrom-JSON -InputObject $RepositoryInformationJSON).$RepositoryName
            $UpdatedRepositoryInformtion = Sync-GitRepositoryToAzureAutomation -RepositoryInformation $RepositoryInformation `
                                                                               -AutomationAccountName $AutomationAccountName `
                                                                               -SubscriptionName $SubscriptionName `
                                                                               -SubscriptionAccessCredential $SubscriptionAccessCredential `
                                                                               -RunbookWorkerAccessCredenial $RunbookWorkerAccessCredential `
                                                                               -RepositoryName $RepositoryName `
                                                                               -RepositoryInformationJSON $RepositoryInformationJSON

            Set-AutomationVariable -Name 'ContinuousIntegration-RepositoryInformation' `
                                   -Value $UpdatedRepositoryInformation
        }
        Catch
        {
            Write-Exception -Stream Warning -Exception $_
        }

        do
        {
            Start-Sleep -Seconds 5
            Checkpoint-Workflow
            $Sleeping = (Get-Date) -lt $NextRun
        } while($Sleeping)
    }
    while($true)
}
