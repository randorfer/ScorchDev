#requires -Version 3
<#
.Synopsis
    Check GIT repository for new commits. If found sync the changes into
    the current SMA environment
#>
Param(
)

$CompletedParams = Write-StartingMessage
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    
$GlobalVars = Get-BatchAutomationVariable -Prefix 'Global' `
                                            -Name 'AutomationAccountName',
                                                'SubscriptionName',
                                                'SubscriptionAccessCredentialName',
                                                'RunbookWorkerAccessCredentialName',
                                                'ResourceGroupName'

$SubscriptionAccessCredential = Get-AutomationPSCredential -Name $GlobalVars.SubscriptionAccessCredentialName
$RunbookWorkerAccessCredential = Get-AutomationPSCredential -Name $GlobalVars.RunbookWorkerAccessCredentialName
        
Try
{
    $RepositoryInformationJSON = Get-AutomationVariable -Name 'ContinuousIntegration-RepositoryInformation'
    Connect-AzureRmAccount -Credential $SubscriptionAccessCredential -SubscriptionName $GlobalVars.SubscriptionName

    $UpdatedRepositoryInformation = Sync-GitRepositoryToAzureAutomation -AutomationAccountName $GlobalVars.AutomationAccountName `
                                                                        -SubscriptionName $GlobalVars.SubscriptionName `
                                                                        -SubscriptionAccessCredential $SubscriptionAccessCredential `
                                                                        -RunbookWorkerAccessCredenial $RunbookWorkerAccessCredential `
                                                                        -RepositoryInformationJSON $RepositoryInformationJSON `
                                                                        -ResourceGroupName $GlobalVars.ResourceGroupName

    Set-AutomationVariable -Name 'ContinuousIntegration-RepositoryInformation' `
                            -Value $UpdatedRepositoryInformation
}
Catch
{
    Write-Exception -Stream Warning -Exception $_
}

Write-CompletedMessage @CompletedParams
