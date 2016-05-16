#  PowerShell deployment example
#  v0.1
#  This script can be used to test the ARM template deployment, or as a reference for building your own deployment script.
param (
)

$CurrentWorkspace = Get-CurrentLocalDevWorkspace
Try
{
    Select-LocalDevWorkspace -Workspace SCOrchDev

    $GlobalVars = Get-BatchAutomationVariable -Prefix 'Global' `
                                              -Name 'AutomationAccountName',
                                                    'SubscriptionName',
                                                    'SubscriptionAccessCredentialName',
                                                    'ResourceGroupName',
                                                    'Tenant',
                                                    'WorkspaceId',
                                                    'GitRepository',
                                                    'HybridWorkerGroup',
                                                    'LocalGitRepositoryRoot',
                                                    'RunbookWorkerAccessCredentialName',
                                                    'SyncTarget',
                                                    'StorageAccountName'


    $LocalGitRepositoryRoot = ($GlobalVars.LocalGitRepositoryRoot | ConvertTo-JSON)
    $GitRepository = ($GlobalVars.GitRepository | ConvertTo-Json)

    $LocalGitRepositoryRoot = $LocalGitRepositoryRoot.Substring(1,$LocalGitRepositoryRoot.Length-2)
    $GitRepository = $GitRepository.Substring(1,$GitRepository.Length-2)

    $SubscriptionAccessCredential = Get-AutomationPSCredential -Name $GlobalVars.SubscriptionAccessCredentialName
    $RunbookWorkerAccessCredential = Get-AutomationPSCredential -Name $GlobalVars.RunbookWorkerAccessCredentialName

    Connect-AzureRmAccount -Credential $SubscriptionAccessCredential -SubscriptionName $GlobalVars.SubscriptionName -Tenant $GlobalVars.Tenant

    $ResourceGroupName = "AzureAutomationDemo$i"
    $ResourceLocation = 'East US 2'
    
    $GlobalParameters = @{
        'ResourceGroupName' = $GlobalVars.ResourceGroupName
        'AutomationAccountName' = $GlobalVars.AutomationAccountName
        'SubscriptionName' = $GlobalVars.SubscriptionName
        'SubscriptionAccessCredentialName' = $GlobalVars.SubscriptionAccessCredentialName
        'SubscriptionAccessCredentialPassword' = $SubscriptionAccessCredential.Password
        'SubscriptionAccessTenant' = $GlobalVars.SubscriptionAccessTenant
        'RunbookWorkerAccessCredentialName' = $GlobalVars.RunbookWorkerAccessCredentialName
        'RunbookWorkerAccessCredentialPassword' = $RunbookWorkerAccessCredential.Password
        'WorkspaceId' = $GlobalVars.WorkspaceId
        'GitRepository' = $GitRepository
        'LocalGitRepositoryroot' = $LocalGitRepositoryRoot
    }

    $AzureAutomationPara
    New-AzureRmResourcegroup -Name $ResourceGroupName -Location $ResourceLocation -Verbose

    New-AzureRmResourceGroupDeployment -Name TestDeployment `
                                       -TemplateFile .\azuredeploy.json `
                                       -jobId ([system.guid]::newguid().guid) `
                                       -Verbose `
                                       @GlobalParameters
}
Catch
{
    Throw
}
Finally
{
    Select-LocalDevWorkspace -Workspace $CurrentWorkspace
}