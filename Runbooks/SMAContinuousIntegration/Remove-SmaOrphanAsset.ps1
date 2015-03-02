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

    $SmaVariables = Get-SmaVariable -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                    -Port $CIVariables.WebservicePort `
                                    -Credential $SMACred
    if($SmaVariables) { $SmaVariableTable = Group-SmaAssetsByRepository -InputObject $SmaVariables }

    $SmaSchedules = Get-SmaSchedule -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                    -Port $CIVariables.WebservicePort `
                                    -Credential $SMACred
    if($SmaSchedules) { $SmaScheduleTable = Group-SmaAssetsByRepository -InputObject $SmaSchedules }

    $RepositoryAssets = Get-GitRepositoryAssetName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.RunbookFolder)"

    if($SmaVariableTable."$RepositoryName")
    {
        $VariableDifferences = Compare-Object -ReferenceObject $SmaVariableTable."$RepositoryName".Name `
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

    if($SmaScheduleTable."$RepositoryName")
    {
        $ScheduleDifferences = Compare-Object -ReferenceObject $SmaScheduleTable."$RepositoryName".Name `
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