$DebugPreference = 'SilentlyContinue'
Select-LocalDevWorkspace SCOrchDev
$GlobalVars = Get-BatchAutomationVariable -Prefix 'Global' `
                                          -Name 'AutomationAccountName', 
                                                'SubscriptionName', 
                                                'SubscriptionAccessCredentialName', 
                                                'HybridWorkerGroup', 
                                                'ResourceGroupName',
                                                'Tenant'

$Password = $env:AccessCredentialPassword | ConvertTo-SecureString -AsPlainText -Force
$SubscriptionAccessCredential = New-Object -TypeName System.Management.Automation.PSCredential `
                                           -ArgumentList $GlobalVars.SubscriptionAccessCredentialName, $Password
Connect-AzureRmAccount -Credential $SubscriptionAccessCredential `
                       -SubscriptionName $GlobalVars.SubscriptionName `
                       -Tenant $GlobalVars.Tenant

$StartTime = (Get-Date)
$AzureRMAutomationParameters = @{
    'ResourceGroupName' = $GlobalVars.ResourceGroupName
    'AutomationAccountName' = $GlobalVars.AutomationAccountName
}

# Wait for any running jobs to completed
Do
{
    $ActivatingJob = Get-AzureRmAutomationJob -RunbookName 'Invoke-GitRepositorySync' -Status Activating @AzureRMAutomationParameters
    $RunningJob = Get-AzureRmAutomationJob -RunbookName 'Invoke-GitRepositorySync' -Status Running @AzureRMAutomationParameters
    $StartingJob= Get-AzureRmAutomationJob -RunbookName 'Invoke-GitRepositorySync' -Status Starting @AzureRMAutomationParameters
    
    if(-not ($ActivatingJob -as [bool] -or $RunningJob -as [bool] -or $StartingJob -as [bool]))
    {
        break
    }
    Write-Verbose -Message 'Waiting for currenty repo sync to complete'
    Start-Sleep -Seconds 5
}
While($true)

$JobStatus = Start-AzureRmAutomationRunbook -Name 'Invoke-GitRepositorySync' `
                                            -RunOn $GlobalVars.HybridWorkerGroup `
                                            @AzureRMAutomationParameters

do
{
    $JobStatus = Get-AzureRmAutomationJob -Id $JobStatus.JobId  `
                                          @AzureRMAutomationParameters
    $JobOutput = Get-AzureRmAutomationJobOutput -Stream Any `
                                                -Id $JobStatus.JobId `
                                                -StartTime $StartTime `
                                                @AzureRMAutomationParameters
    $StartTime = (Get-Date)
    $JobOutput | Format-Table Stream, Summary
    if($JobStatus.Status -notin ('New', 'Activating' , 'Running'))
    {
        break
    }
    Start-Sleep -Seconds 5
}
while($true)