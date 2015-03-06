<#
    .Synopsis
        Checks a SMA environment and removes any modules that are not found
        in the local psmodulepath
#>
Workflow Remove-SmaOrphanModule
{
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

    $SmaModule = Get-SmaModule -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                               -Port $CIVariables.WebservicePort `
                               -Credential $SMACred

    $LocalModule = Get-Module -ListAvailable -Refresh -Verbose:$false

    if(-not ($SmaModule -and $LocalModule))
    {
        if(-not $SmaModule)   { Write-Warning -Message 'No modules found in SMA. Not cleaning orphan modules' }
        if(-not $LocalModule) { Write-Warning -Message 'No modules found in local PSModule Path. Not cleaning orphan modules' }
    }
    else
    {
        $ModuleDifference = Compare-Object -ReferenceObject  $SmaModule.ModuleName `
                                           -DifferenceObject $LocalModule.Name
        Foreach($Difference in $ModuleDifference)
        {
            if($Difference.SideIndicator -eq '<=')
            {
                Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                Remove-SmaModule -Name $Difference.InputObject `
                                 -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                 -Port $CIVariables.WebservicePort `
                                 -Credential $SMACred
                Write-Verbose -Message "[$($Difference.InputObject)] Removed from SMA"
            }
        }
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}