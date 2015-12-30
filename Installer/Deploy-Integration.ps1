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
    [pscredential]
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
    $Tenant,

     [Parameter(
        Mandatory = $False
    )]
    [String]
    $StorageAccountName
)
    
$CompletedParams = Write-StartingMessage -CommandName 'Deploy Integration'
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

$CurrentCommit = Get-GitCurrentCommit -Path $Path

Foreach($RunbookFile in (Get-ChildItem -Path "$($Path)\Runbooks" -Recurse -Filter *.ps1))
{
    Try
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
    Catch
    {
        Write-Exception -Exception $_ -Stream Warning
    }
}
Foreach($SettingsFile in (Get-ChildItem -Path "$($Path)\Globals" -Recurse -Filter *.json))
{
    Try
    {
        Publish-AzureAutomationSettingsFileChange -FilePath $SettingsFile.FullName `
                                              -CurrentCommit $CurrentCommit `
                                              -RepositoryName $RepositoryName `
                                              -Credential $Credential `
                                              -AutomationAccountName $AutomationAccountName `
                                              -SubscriptionName $SubscriptionName `
                                              -ResourceGroupName $ResourceGroupName `
                                              -Tenant $Tenant
    }
    Catch
    {
        Write-Exception -Exception $_ -Stream Warning
    }
}

Foreach($SettingsFile in (Get-ChildItem -Path "$($Path)\DSC" -Recurse -Filter *.PS1))
{
    Try
    {
        Publish-AzureAutomationDSCChange  -FilePath $SettingsFile.FullName `
                                              -CurrentCommit $CurrentCommit `
                                              -RepositoryName $RepositoryName `
                                              -Credential $Credential `
                                              -AutomationAccountName $AutomationAccountName `
                                              -SubscriptionName $SubscriptionName `
                                              -ResourceGroupName $ResourceGroupName `
                                              -Tenant $Tenant
    }
    Catch
    {
        Write-Exception -Exception $_ -Stream Warning
    }
}


Foreach($SettingsFile in (Get-ChildItem -Path "$($Path)\PowerShellModules" -Recurse -Filter *.psd1))
{
    Try
    {
        Publish-AzureAutomationPowerShellModule -FilePath $SettingsFile.FullName `
                                                -CurrentCommit $CurrentCommit `
                                                -RepositoryName $RepositoryName `
                                                -Credential $Credential `
                                                -AutomationAccountName $AutomationAccountName `
                                                -SubscriptionName $SubscriptionName `
                                                -ResourceGroupName $ResourceGroupName `
                                                -Tenant $Tenant `
                                                -StorageAccountName $StorageAccountName
    }
    Catch
    {
        Write-Exception -Exception $_ -Stream Warning
    }
}
Write-CompletedMessage @CompletedParams