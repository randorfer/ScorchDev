Param(
    [Parameter(
        Mandatory = $True
    )]
    [String]
    $Path,

    [Parameter(
        Mandatory = $True
    )]
    [String]
    $RepositoryName,

    [Parameter(
        Mandatory = $True
    )]
    [String]
    $Credential,

    [Parameter(
        Mandatory = $True
    )]
    [String]
    $AutomationAccountName,

    [Parameter(
        Mandatory = $True
    )]
    [String]
    $SubscriptionName,

    [Parameter(
        Mandatory = $True
    )]
    [String]
    $ResourceGroupName,

    [Parameter(
        Mandatory = $False
    )]
    [String]
    $Tenant
)
    
$CompletedParams = Write-StartingMessage -CommandName 'Deploy Integration'
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

$CurrentCommit = Get-GitCurrentCommit -Path $Path

Foreach($RunbookFile in (Get-ChildItem -Path "$($Path)\Runbooks" -Recurse -Filter *.ps1))
{
    Publish-AzureAutomationRunbookChange -FilePath $RunbookFile.FullName `
                                         -CurrentCommit $CurrentCommit `
                                         -RepositoryName $RepositoryName `
                                         -Credential $Credential `
                                         -AutomationAccountName $AutomationAccountName `
                                         -SubscriptionName $SubscriptionName `
                                         -ResourceGroupName $ResourceGroupName `
                                         -Tenant $Tenant
}
Foreach($SettingsFile in (Get-ChildItem -Path "$($Path)\Globals" -Recurse -Filter *.json))
{
    Publish-AzureAutomationSettingsFileChange -FilePath $RunbookFile.FullName `
                                              -CurrentCommit $CurrentCommit `
                                              -RepositoryName $RepositoryName `
                                              -Credential $Credential `
                                              -AutomationAccountName $AutomationAccountName `
                                              -SubscriptionName $SubscriptionName `
                                              -ResourceGroupName $ResourceGroupName `
                                              -Tenant $Tenant
}
Write-CompletedMessage @CompletedParams