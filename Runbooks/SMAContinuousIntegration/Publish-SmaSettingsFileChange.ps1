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
    
    Write-Verbose -Message "[$FilePath] Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

    Try
    {
        $Variables = ConvertFrom-PSCustomObject (ConvertFrom-JSON (Get-SmaVariablesFromFile -FilePath $FilePath))
        foreach($VariableName in $Variables.Keys)
        {
            Write-Verbose -Message "[$VariableName] Updating"
            $Variable = $Variables."$VariableName"
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
            $SmaVariable = Get-SmaVariable -Name $VariableName `
                                           -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                           -Port $CIVariables.WebservicePort `
                                           -Credential $SMACred
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
            if(Test-IsNullOrEmpty $SmaVariable.VariableId.Guid)
            {
                Write-Verbose -Message "[$($VariableName)] is a New Variable"
                $VariableDescription = "$($Variable.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                $NewVersion = $True
            }
            else
            {
                Write-Verbose -Message "[$($VariableName)] is an existing Variable"
                $TagUpdate = ConvertFrom-JSON( New-SmaChangesetTagLine -TagLine $SmaVariable.Description`
                                                         -CurrentCommit $CurrentCommit `
                                                         -RepositoryName $RepositoryName )
                $VariableDescription = "$($TagUpdate.TagLine)"
                $NewVersion = $TagUpdate.NewVersion
            }
            if($NewVersion)
            {
                if(ConvertTo-Boolean $Variable.isEncrypted)
                {
                    $CreateEncryptedVariable = Set-SmaVariable -Name $VariableName `
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
                    $CreateNonEncryptedVariable = Set-SmaVariable -Name $VariableName `
													              -Value $Variable.Value `
														          -Description $VariableDescription `
														          -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                                  -Port $CIVariables.WebservicePort `
                                                                  -Credential $SMACred
                }
            }
            else
            {
                Write-Verbose -Message "[$($VariableName)] Is not a new version. Skipping"
            }
            Write-Verbose -Message "[$($VariableName)] Finished Updating"
        }

        $Schedules = ConvertFrom-PSCustomObject ( ConvertFrom-JSON (Get-SmaSchedulesFromFile -FilePath $FilePath) )
        foreach($ScheduleName in $Schedules.Keys)
        {
            Write-Verbose -Message "[$ScheduleName] Updating"
            try
            {
                $Schedule = $Schedules."$ScheduleName"
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                $SmaSchedule = Get-SmaSchedule -Name $ScheduleName `
                                               -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                               -Port $CIVariables.WebservicePort `
                                               -Credential $SMACred
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                if(Test-IsNullOrEmpty $SmaSchedule.ScheduleId.Guid)
                {
                    Write-Verbose -Message "[$($ScheduleName)] is a New Schedule"
                    $ScheduleDescription = "$($Schedule.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                    $NewVersion = $True
                }
                else
                {
                    Write-Verbose -Message "[$($ScheduleName)] is an existing Schedule"
                    $TagUpdate = ConvertFrom-JSON( New-SmaChangesetTagLine -TagLine $SmaVariable.Description`
                                                             -CurrentCommit $CurrentCommit `
                                                             -RepositoryName $RepositoryName )
                    $ScheduleDescription = "$($TagUpdate.TagLine)"
                    $NewVersion = $TagUpdate.NewVersion
                }
                if($NewVersion)
                {
                    $CreateSchedule = Set-SmaSchedule -Name $ScheduleName `
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
                                        -Property @{ 'ScheduleName' = $ScheduleName ;
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
                                                         -ScheduleName $ScheduleName `
                                                         -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                         -Port $CIVariables.WebservicePort `
                                                         -Parameters $Parameters `
                                                         -Credential $SMACred
                        if(Test-IsNullOrEmpty $RunbookStart)
                        {
                            Throw-Exception -Type 'ScheduleFailedToSet' `
                                            -Message 'Failed to set the schedule on the target runbook' `
                                            -Property @{ 'ScheduleName' = $ScheduleName ;
                                                         'RunbookName' = $Schedule.RunbookName ; 
                                                         'Parameters' = $(ConvertTo-Json $Parameters) }
                        }
                    }
                    catch
                    {
                        Remove-SmaSchedule -Name $ScheduleName `
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
            Write-Verbose -Message "[$($ScheduleName)] Finished Updating"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "[$FilePath] Finished [$WorkflowCommandName]"
}