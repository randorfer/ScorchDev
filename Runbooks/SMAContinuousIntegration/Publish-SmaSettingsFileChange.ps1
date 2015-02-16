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
                $VariableDescription = "$($Variable.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
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
            if($NewVersion)
            {
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
            }
            Write-Verbose -Message "[$($Variable.Name)] Finished Updating"
        }

        $Schedules = Get-SmaSchedulesFromFile -FilePath $FilePath
        foreach($ScheduleJSON in $Schedules)
        {
            Write-Verbose -Message "[$ScheduleJSON] Updating"
            try
            {
                $Schedule = ConvertFrom-Json $ScheduleJSON
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                $SmaSchedule = Get-SmaSchedule -Name $Schedule.Name `
                                               -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                               -Port $CIVariables.WebservicePort `
                                               -Credential $SMACred
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                if(Test-IsNullOrEmpty $SmaSchedule.ScheduleId.Guid)
                {
                    Write-Verbose -Message "[$($Schedule.Name)] is a New Schedule"
                    $ScheduleDescription = "$($Schedule.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                    $NewVersion = $True
                }
                else
                {
                    Write-Verbose -Message "[$($Schedule.Name)] is an existing Variable"
                    $TagUpdateJSON = New-SmaChangesetTagLine -TagLine $SmaSchedule.Description`
                                                             -CurrentCommit $CurrentCommit `
                                                             -RepositoryName $RepositoryName
                    $TagUpdate = ConvertFrom-Json $TagUpdateJSON
                    $ScheduleDescription = "$($Variable.Description)`n`r$($TagUpdate.TagLine)"
                    $NewVersion = $TagUpdate.NewVersion
                }
                if($NewVersion)
                {
                    $CreateSchedule = Set-SmaSchedule -Name $Schedule.Name `
                                                      -Description $ScheduleDescription `
                                                      -ScheduleType DailySchedule `
                                                      -DayInterval $Schedule.DayInterval `
                                                      -StartTime $Schedule.NextRun `
                                                      -ExpiryTime $Schedule.ExpirationTime `
                                                      -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                      -Port $CIVariables.WebservicePort `
                                                      -Credential $SMACred

                    if(Test-IsNullOrEmpty $CreateSchedule)
                    {
                        Throw-Exception -Type 'ScheduleFailedToCreate' `
                                        -Message 'Failed to create the schedule' `
                                        -Property @{ 'ScheduleName' = $Schedule.Name ;
                                                     'Description' = $ScheduleDescription;
                                                     'ScheduleType' = 'DailySchedule' ;
                                                     'DayInterval' = $Schedule.DayInterval ;
                                                     'StartTime' = $Schedule.NextRun ;
                                                     'ExpiryTime' = $Schedule.ExpirationTime ;
                                                     'WebServiceEndpoint' = $CIVariables.WebserviceEndpoint ;
                                                     'Port' = $CIVariables.WebservicePort ;
                                                     'Credential' = $SMACred.UserName }
                    }
                    try
                    {
                        $Parameters   = ConvertFrom-PSCustomObject -InputObject $Schedule.Parameter `
                                                                   -MemberType NoteProperty `

                        $RunbookStart = Start-SmaRunbook -Name $schedule.RunbookName `
                                                         -ScheduleName $Schedule.Name `
                                                         -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                         -Port $CIVariables.WebservicePort `
                                                         -Parameters $Parameters `
                                                         -Credential $SMACred
                        if(Test-IsNullOrEmpty $RunbookStart)
                        {
                            Throw-Exception -Type 'ScheduleFailedToSet' `
                                            -Message 'Failed to set the schedule on the target runbook' `
                                            -Property @{ 'ScheduleName' = $Schedule.Name ;
                                                         'RunbookName' = $Schedule.RunbookName ; 
                                                         'Parameters' = $(ConvertTo-Json $Parameters) }
                        }
                    }
                    catch
                    {
                        Remove-SmaSchedule -Name $Schedule.Name `
                                           -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                           -Port $CIVariables.WebservicePort `
                                           -Credential $SMACred `
                                           -Force
                        Write-Exception $_ -Stream Warning
                    }
                                                  
                }
            }
            catch
            {
                Write-Exception $_ -Stream Warning
            }
            Write-Verbose -Message "[$($Schedule.Name)] Finished Updating"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}