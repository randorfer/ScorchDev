#  PowerShell deployment example
#  v0.1
#  This script can be used to test the ARM template deployment, or as a reference for building your own deployment script.
param (
	[Parameter(Mandatory=$false)]
	[int]$i
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
                                                    'Tenant'

    $Vars = Get-BatchAutomationVariable -Prefix 'AzureAutomation' `
                                        -Name 'WorkspaceId'
    $SubscriptionAccessCredential = Get-AutomationPSCredential -Name $GlobalVars.SubscriptionAccessCredentialName

    Connect-AzureRmAccount -Credential $SubscriptionAccessCredential -SubscriptionName $GlobalVars.SubscriptionName -Tenant $GlobalVars.Tenant

    $ResourceGroupName = "AzureAutomationDemo$i"
    $ResourceLocation = 'East US 2'
    $AccountName = "AutomationAccountTest$i"

    $gitRepository = '{\"https://github.com/randorfer/RunbookExample\":\"vNext\",\"https://github.com/randorfer/SCOrchDev\":\"vNext\"}'
    $localGitRepositoryRoot = 'c:\\git'
    $subscriptionName = 'Microsoft Azure Internal Consumption'
    New-AzureRmResourcegroup -Name $ResourceGroupName -Location 'East US 2' -Verbose

    $NewGUID = [system.guid]::newguid().guid

    New-AzureRmResourceGroupDeployment -Name TestDeployment `
                                       -ResourceGroupName $ResourceGroupName `
                                       -TemplateFile .\azuredeploy.json `
                                       -automationAccountName $AccountName `
                                       -workspaceId $Vars.WorkspaceId `
                                       -SubscriptionAccessCredentialName $GlobalVars.SubscriptionAccessCredentialName `
                                       -SubscriptionAccessCredentialPassword $SubscriptionAccessCredential.Password `
                                       -SubscriptionAccessTenant $GlobalVars.Tenant `
                                       -SubscriptionName $subscriptionName `
                                       -gitRepository $gitRepository `
                                       -localGitRepositoryRoot $localGitRepositoryRoot `
                                       -jobId $NewGUID `
                                       -Verbose
}
Catch
{
    Throw
}
Finally
{
    Select-LocalDevWorkspace -Workspace $CurrentWorkspace
}