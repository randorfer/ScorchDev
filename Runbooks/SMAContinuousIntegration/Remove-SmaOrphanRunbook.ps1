<#
    .Synopsis
        Checks a SMA environment and removes any runbooks tagged
        with the current repository that are no longer found in
        the repository

    .Parameter RepositoryName
        The name of the repository
#>
Workflow Remove-SmaOrphanRunbook
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

    $SmaRunbooks = ConvertTo-Hashtable -InputObject(Get-SMARunbookPaged -WebserviceEndpoint $CIVariables.WebserviceEndpoint `
                                                                        -Port $CIVariables.WebservicePort `
                                                                        -Credential $SMACred) `
                                       -KeyName 'Tags' `
                                       -KeyFilterScript { 
                                                            Param($KeyName)
                                                            if($KeyName -match 'RepositoryName:([^;]+);')
                                                            {
                                                                $Matches[1]
                                                            }
                                                        }
    
    
    $RepositoryWorkflows = Get-GitRepositoryWorkflowName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.RunbookFolder)"
    $Differences = Compare-Object -ReferenceObject $SmaRunbooks.$RepositoryName.RunbookName `
                                  -DifferenceObject $RepositoryWorkflows
    
    Foreach($Difference in $Differences)
    {
        if($Difference.SideIndicator -eq '<=')
        {
            Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
            Remove-SmaRunbook -Name $Difference.InputObject `
                              -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                              -Port $CIVariables.WebservicePort `
                              -Credential $SMACred
            Write-Verbose -Message "[$($Difference.InputObject)] Removed from SMA"
        }
    }

    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}