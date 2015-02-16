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

    $RepositoryInformation = $CIVariables.RepositoryInformation."$RepositoryName"

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

    
    


    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}