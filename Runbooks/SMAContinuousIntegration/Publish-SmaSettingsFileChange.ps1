<#
    .Synopsis
        Takes a json file and publishes all schedules and variables from it into SMA
    
    .Parameter FilePath
        The path to the settings file to process

    .Parameter CurrentCommit
        The current commit to tag the variables and schedules with

    .Parameter RepositoryName
        The Repository Name that will 'own' the variables and schedules
#>
Workflow Publish-SMASettingsFileChange
{
    Param( [Parameter(Mandatory=$True)][String] $FilePath,
           [Parameter(Mandatory=$True)][String] $CurrentCommit,
           [Parameter(Mandatory=$True)][String] $RepositoryName)
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

    Try
    {
        $Variables = Get-SmaVariablesFromFile -FilePath $FilePath
        foreach($VariableJSON in $Variables)
        {
            Write-Verbose -Message "[$VariableJSON] Updating"
            $Variable = ConvertFrom-Json $VariableJSON
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
            $SmaVariable = Get-SmaVariable -Name $Variable.Name `
                                           -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                           -Port $CIVariables.WebservicePort `
                                           -Credential $SMACred
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
            if(Test-IsNullOrEmpty $SmaVariable.VariableId.Guid)
            {
                Write-Verbose -Message "[$($Variable.Name)] is a New Variable"
                $VariableDescription = "$($Variable.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit)__"
                $NewVersion = $True
            }
            else
            {
                Write-Verbose -Message "[$($Variable.Name)] is an existing Variable"
                $TagUpdateJSON = New-SmaChangesetTagLine -TagLine $SmaVariable.Description`
                                                         -CurrentCommit $CurrentCommit `
                                                         -RepositoryName $RepositoryName
                $TagUpdate = ConvertFrom-Json $TagUpdateJSON
                $VariableDescription = "$($Variable.Description)`n`r$($TagUpdate.TagLine)"
                $NewVersion = $TagUpdate.NewVersion
            }
            
            if(ConvertTo-Boolean $Variable.isEncrypted)
            {
                $CreateEncryptedVariable = Set-SmaVariable -Name $Variable.Name `
													       -Value $Variable.Value `
														   -Description $VariableDescription `
                                                           -Encrypted `
														   -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                           -Port $CIVariables.WebservicePort `
                                                           -Credential $SMACred `
                                                           -Force
            }
            else
            {
                $CreateNonEncryptedVariable = Set-SmaVariable -Name $Variable.Name `
													          -Value $Variable.Value `
														      -Description $VariableDescription `
														      -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                              -Port $CIVariables.WebservicePort `
                                                              -Credential $SMACred
            }
            Write-Verbose -Message "[$($Variable.Name)] Finished Updating"
        }

        $Schedules = Get-SmaSchedulesFromFile -FilePath $FilePath
        foreach($ScheduleJSON in $Schedules)
        {
            Write-Verbose -Message "[$ScheduleJSON] Updating"
            $Schedule = ConvertFrom-Json $ScheduleJSON
            Write-Verbose -Message "[$($Variable.Name)] Finished Updating"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}