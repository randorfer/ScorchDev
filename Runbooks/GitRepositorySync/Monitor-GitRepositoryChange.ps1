#requires -Version 3
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
    
    $GlobalVars = Get-BatchAutomationVariable -Prefix 'Global' `
                                              -Name 'AutomationAccountName',
                                                    'SubscriptionName',
                                                    'SubscriptionAccessCredentialName',
                                                    'ResourceGroupName'
    
    $Vars = Get-BatchAutomationVariable -Prefix 'ContinuousIntegration' `
                                        -Name 'RunbookWorkerAccessCredentialName', `
                                              'RepositoryName'
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
                                                                               -RepositoryInformationJSON $RepositoryInformationJSON `
                                                                               -ResourceGroupName $ResourceGroupName

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
