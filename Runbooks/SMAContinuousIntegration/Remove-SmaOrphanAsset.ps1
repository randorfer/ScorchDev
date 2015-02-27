<#
    .Synopsis
        Checks a SMA environment and removes any global assets tagged
        with the current repository that are no longer found in
        the repository

    .Parameter RepositoryName
        The name of the repository
#>
Workflow Remove-SmaOrphanAsset
{
   Param($RepositoryName)

    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('RepositoryInformation',
                                                       'SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

    $RepositoryInformation = (ConvertFrom-JSON -InputObject $CIVariables.RepositoryInformation)."$RepositoryName"

    $SmaVariables = Group-SmaAssetsByRepository -InputObject ( Get-SmaVariable -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                                       -Port $CIVariables.WebservicePort `
                                                                       -Credential $SMACred )

    $SmaSchedules = Group-SmaAssetsByRepository -InputObject ( Get-SmaSchedule -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                                       -Port $CIVariables.WebservicePort `
                                                                       -Credential $SMACred )

    $RepositoryAssets = Get-GitRepositoryAssetName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.RunbookFolder)"

    if($SmaVariables."$RepositoryName")
    {
        $VariableDifferences = Compare-Object -ReferenceObject $SmaVariables."$RepositoryName".Name `
                                              -DifferenceObject $RepositoryAssets.Variable
        Foreach($Difference in $VariableDifferences)
        {
            if($Difference.SideIndicator -eq '<=')
            {
                Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                Remove-SmaVariable -Name $Difference.InputObject `
                                   -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                   -Port $CIVariables.WebservicePort `
                                   -Credential $SMACred
                Write-Verbose -Message "[$($Difference.InputObject)] Removed from SMA"
            }
        }
    }
    else
    {
        Write-Warning -Message "[$RepositoryName] No Variables found in environment for this repository" `
                      -WarningAction Continue
    }

    if($SmaSchedules."$RepositoryName")
    {
        $ScheduleDifferences = Compare-Object -ReferenceObject $SmaSchedules."$RepositoryName".Name `
                                              -DifferenceObject $RepositoryAssets.Schedule
        Foreach($Difference in $ScheduleDifferences)
        {
            if($Difference.SideIndicator -eq '<=')
            {
                Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                Remove-SmaSchedule -Name $Difference.InputObject `
                                   -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                   -Port $CIVariables.WebservicePort `
                                   -Credential $SMACred
                Write-Verbose -Message "[$($Difference.InputObject)] Removed from SMA"
            }
        }
    }
    else
    {
        Write-Warning -Message "[$RepositoryName] No Schedules found in environment for this repository" `
                      -WarningAction Continue
    }

    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}