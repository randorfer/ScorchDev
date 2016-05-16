<#
.Synopsis
    Check GIT repository for new commits. If found sync the changes into
    the Azure Automation Environment
#>
Param(
)

$CompletedParams = Write-StartingMessage -CommandName 'Invoke-GitRepositorySync'
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    
$GlobalVars = Get-BatchAutomationVariable -Prefix 'zzGlobal' `
                                          -Name 'AutomationAccountName',
                                                'SubscriptionName',
                                                'SubscriptionAccessCredentialName',
                                                'RunbookWorkerAccessCredentialName',
                                                'ResourceGroupName',
                                                'Tenant',
                                                'StorageAccountName',
                                                'SyncTarget',
                                                'GitRepositoryCurrentCommit',
                                                'LocalGitRepositoryRoot'

$SubscriptionAccessCredential = Get-AutomationPSCredential -Name $GlobalVars.SubscriptionAccessCredentialName
$RunbookWorkerAccessCredential = Get-AutomationPSCredential -Name $GlobalVars.RunbookWorkerAccessCredentialName
        
Try
{
    Connect-AzureRmAccount -Credential $SubscriptionAccessCredential -SubscriptionName $GlobalVars.SubscriptionName -Tenant $GlobalVars.Tenant
    
    $UpdatedGitRepositoryCurrentCommit = Sync-GitRepositoryToAzureAutomation -AutomationAccountName $GlobalVars.AutomationAccountName `
                                                                             -SubscriptionName $GlobalVars.SubscriptionName `
                                                                             -SubscriptionAccessCredential $SubscriptionAccessCredential `
                                                                             -RunbookWorkerAccessCredential $RunbookWorkerAccessCredential `
                                                                             -ResourceGroupName $GlobalVars.ResourceGroupName `
                                                                             -Tenant $GlobalVars.Tenant `
                                                                             -StorageAccountName $GlobalVars.StorageAccountName `
                                                                             -SyncTarget $GlobalVars.SyncTarget `
                                                                             -GitRepositoryCurrentCommit $GlobalVars.GitRepositoryCurrentCommit `
                                                                             -LocalGitRepositoryRoot $GlobalVars.LocalGitRepositoryRoot

    Set-AutomationVariable -Name 'Global-GitRepositoryCurrentCommit' `
                           -Value $UpdatedGitRepositoryCurrentCommit
}
Catch
{
    Write-Exception -Stream Warning -Exception $_
}

Write-CompletedMessage @CompletedParams
