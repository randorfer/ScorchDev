#requires -Version 3 -Modules Azure, SCOrchDev-Exception, SCOrchDev-GitIntegration, SCOrchDev-Utility
<#
    .Synopsis
        Takes a ps1 file and publishes it to the current Azure Automation environment.
    
    .Parameter FilePath
        The full path to the script file

    .Parameter CurrentCommit
        The current commit to store this version under

    .Parameter RepositoryName
        The name of the repository that will be listed as the 'owner' of this
        runbook
#>
Function Publish-AzureAutomationRunbookChange
{
    Param(
        [Parameter(Mandatory = $True)]
        [String] 
        $FilePath,
        
        [Parameter(Mandatory = $True)]
        [String]
        $CurrentCommit,

        [Parameter(Mandatory = $True)]
        [String]
        $RepositoryName,

        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $True)]
        [String]
        $AutomationAccountName,

        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName
    )
    
    Write-Verbose -Message "[$FilePath] Starting [Publish-AzureAutomationRunbookChange]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureAutomationAccount -Credential $Credential `
                                       -SubscriptionName $SubscriptionName `
                                       -AutomationAccountName $AutomationAccountName

        $WorkflowName = Get-WorkflowNameFromFile -FilePath $FilePath
        
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        $Runbook = Get-AzureAutomationRunbook -Name $WorkflowName `
                                              -AutomationAccountName $AutomationAccountName
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        if($Runbook -as [bool])
        {
            Write-Verbose -Message "[$WorkflowName] Update"
            $TagUpdateJSON = New-ChangesetTagLine -TagLine ($Runbook.Tags -join ';') `
                                                  -CurrentCommit $CurrentCommit `
                                                  -RepositoryName $RepositoryName
            $TagUpdate = ConvertFrom-Json -InputObject $TagUpdateJSON
            $TagLine = $TagUpdate.TagLine
            $NewVersion = $TagUpdate.NewVersion
            if($NewVersion)
            {
                $Runbook = Set-AzureAutomationRunbookDefinition -Name $WorkflowName `
                                                                -Path $FilePath `
                                                                -Overwrite `
                                                                -AutomationAccountName $AutomationAccountName
                $TagUpdate = Set-AzureAutomationRunbook -Name $WorkflowName `
                                                        -Tags $TagLine.Split(';') `
                                                        -AutomationAccountName $AutomationAccountName
            }
            else
            {
                Write-Verbose -Message "[$WorkflowName] Already is at commit [$CurrentCommit]"
            }
        }
        else
        {
            Write-Verbose -Message "[$WorkflowName] Initial Import"
            
            $TagLine = "RepositoryName:$RepositoryName;CurrentCommit:$CurrentCommit;"
            $Runbook = New-AzureAutomationRunbook -Path $FilePath `
                                                  -Tags $TagLine.Split(';') `
                                                  -AutomationAccountName $AutomationAccountName
            
            $NewVersion = $True
        }
        if($NewVersion)
        {
            $Null = Publish-AzureAutomationRunbook -Name $WorkflowName `
                                                   -AutomationAccountName $AutomationAccountName
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "[$FilePath] Finished [Publish-AzureAutomationRunbookChange]"
}
<#
.Synopsis
    Takes a json file and publishes all schedules and variables from it into Azure Automation
    
.Parameter FilePath
    The path to the settings file to process

.Parameter CurrentCommit
    The current commit to tag the variables and schedules with

.Parameter RepositoryName
    The Repository Name that will 'own' the variables and schedules
#>
Function Publish-AzureAutomationSettingsFileChange
{
    Param( 
        [Parameter(Mandatory = $True)]
        [String] 
        $FilePath,
        
        [Parameter(Mandatory = $True)]
        [String]
        $CurrentCommit,

        [Parameter(Mandatory = $True)]
        [String]
        $RepositoryName,

        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $True)]
        [String]
        $AutomationAccountName,

        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName
    )
    
    Write-Verbose -Message "[$FilePath] Starting [Publish-AzureAutomationSettingsFileChange]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureAutomationAccount -Credential $Credential `
                                       -SubscriptionName $SubscriptionName `
                                       -AutomationAccountName $AutomationAccountName

        $VariablesJSON = Get-GlobalFromFile -FilePath $FilePath -GlobalType Variables
        $Variables = $VariablesJSON | ConvertFrom-JSON | ConvertFrom-PSCustomObject
        foreach($VariableName in $Variables.Keys)
        {
            Try
            {
                Write-Verbose -Message "[$VariableName] Updating"
                $Variable = $Variables."$VariableName"
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                $AzureAutomationVariable = Get-AzureAutomationVariable -Name $VariableName `
                                                                       -AutomationAccountName $AutomationAccountName
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                if($AzureAutomationVariable -as [bool])
                {
                    Write-Verbose -Message "[$($VariableName)] is an existing Variable"
                    $TagUpdateJSON = New-ChangesetTagLine -TagLine $AzureAutomationVariable.Description`
                                                          -CurrentCommit $CurrentCommit `
                                                          -RepositoryName $RepositoryName
                    $TagUpdate = $TagUpdateJSON | ConvertFrom-Json
                    $VariableDescription = "$($TagUpdate.TagLine)"
                    $NewVersion = $TagUpdate.NewVersion
                    $NewVariable = $False
                }
                else
                {
                    Write-Verbose -Message "[$($VariableName)] is a New Variable"
                    $VariableDescription = "$($Variable.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                    $NewVersion = $True
                    $NewVariable = $True
                }
                if($NewVersion)
                {
                    $VariableParameters = @{
                        'Name' = $VariableName ;
                        'Value' = $Variable.Value ;
                        'Encrypted' = $Variable.isEncrypted ;
                        'AutomationAccountName' = $AutomationAccountName
                    }
                    if($NewVariable)
                    {
                        $Null = New-AzureAutomationVariable @VariableParameters `
                                                            -Description $VariableDescription
                    }
                    else
                    {
                        $Null = Set-AzureAutomationVariable @VariableParameters
                        $Null = Set-AzureAutomationVariable -Name $VariableName `
                                                            -Description $VariableDescription `
                                                            -AutomationAccountName $AutomationAccountName
                    }
                }
                else
                {
                    Write-Verbose -Message "[$($VariableName)] Is not a new version. Skipping"
                }
                Write-Verbose -Message "[$($VariableName)] Finished Updating"
            }
            Catch
            {
                $Exception = New-Exception -Type 'VariablePublishFailure' `
                                           -Message 'Failed to publish a variable to Azure Automation' `
                                           -Property @{
                    'ErrorMessage' = Convert-ExceptionToString $_ ;
                    'VariableName' = $VariableName ;
                }
                Write-Warning -Message $Exception -WarningAction Continue
            }
        }
        $SchedulesJSON = Get-GlobalFromFile -FilePath $FilePath -GlobalType Schedules
        $Schedules = $SchedulesJSON | ConvertFrom-JSON | ConvertFrom-PSCustomObject
        foreach($ScheduleName in $Schedules.Keys)
        {
            Write-Verbose -Message "[$ScheduleName] Updating"
            try
            {
                $Schedule = $Schedules."$ScheduleName"
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                $AzureAutomationSchedule = Get-AzureAutomationSchedule -Name $ScheduleName `
                                                                       -AutomationAccountName $AutomationAccountName
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                if($AzureAutomationSchedule -as [bool])
                {
                    Write-Verbose -Message "[$($ScheduleName)] is an existing Schedule"
                    $TagUpdateJSON = New-ChangesetTagLine -TagLine $Schedule.Description`
                                                          -CurrentCommit $CurrentCommit `
                                                          -RepositoryName $RepositoryName
                    $TagUpdate = ConvertFrom-Json -InputObject $TagUpdateJSON
                    $ScheduleDescription = "$($TagUpdate.TagLine)"
                    $NewVersion = $TagUpdate.NewVersion
                    if($NewVersion)
                    {
                        Write-Verbose -Message "[$($ScheduleName)] is an Updated Schedule. Deleting to re-create"
                        Remove-AzureAutomationSchedule -Name $ScheduleName `
                                                       -Force `
                                                       -AutomationAccountName $AutomationAccountName
                    }
                }
                else
                {
                    Write-Verbose -Message "[$($ScheduleName)] is a New Schedule"
                    $ScheduleDescription = "$($Schedule.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                    
                    $NewVersion = $True
                }
                if($NewVersion)
                {
                    $CreateSchedule = New-AzureAutomationSchedule -Name $ScheduleName `
                                                                  -Description $ScheduleDescription `
                                                                  -DayInterval $Schedule.DayInterval `
                                                                  -StartTime $Schedule.NextRun `
                                                                  -ExpiryTime $Schedule.ExpirationTime `
                                                                  -AutomationAccountName $AutomationAccountName
                    if(-not ($CreateSchedule -as [bool]))
                    {
                        Throw-Exception -Type 'ScheduleFailedToCreate' `
                                        -Message 'Failed to create the schedule' `
                                        -Property @{
                            'ScheduleName'     = $ScheduleName
                            'Description'      = $ScheduleDescription
                            'DayInterval'      = $Schedule.DayInterval
                            'StartTime'        = $Schedule.NextRun
                            'ExpiryTime'       = $Schedule.ExpirationTime
                            'AutomationAccountName' = $AutomationAccountName
                        }
                    }
                    try
                    {
                        $Parameters = ConvertFrom-PSCustomObject -InputObject $Schedule.Parameter `
                                                                 -MemberType NoteProperty
                        $Register = Register-AzureAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName `
                                                                             -RunbookName $Schedule.RunbookName `
                                                                             -ScheduleName $ScheduleName `
                                                                             -Parameters $Parameters
                        if(-not($Register -as [bool]))
                        {
                            Throw-Exception -Type 'ScheduleFailedToSet' `
                                            -Message 'Failed to set the schedule on the target runbook' `
                                            -Property @{
                                'ScheduleName' = $ScheduleName ;
                                'RunbookName' = $Schedule.RunbookName ;
                                'Parameters' = $(ConvertTo-Json -InputObject $Parameters) ;
                                'AutomationAccountName' = $AutomationAccountName
                            }
                        }
                    }
                    catch
                    {
                        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                        Remove-AzureAutomationSchedule -Name $ScheduleName `
                                                       -Force `
                                                       -AutomationAccountName $AutomationAccountName
                                                       $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Continue
                        Write-Exception -Exception $_ -Stream Warning
                    }
                }
            }
            catch
            {
                Write-Exception -Exception $_ -Stream Warning
            }
            Write-Verbose -Message "[$($ScheduleName)] Finished Updating"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "[$FilePath] Finished [Publish-AzureAutomationSettingsFileChange]"
}
<#
.Synopsis
    Checks an Azure Automation environment and removes any global assets tagged
    with the current repository that are no longer found in
    the repository

.Parameter RepositoryName
    The name of the repository
#>
Function Remove-AzureAutomationOrphanAsset
{
    Param(
        [Parameter(Mandatory = $True)]
        [String]
        $RepositoryName,

        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $True)]
        [String]
        $AutomationAccountName,

        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [PSCustomObject] 
        $RepositoryInformation
    )

    Write-Verbose -Message 'Starting [Remove-AzureAutomationOrphanAsset]'
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Try
    {
        Connect-AzureAutomationAccount -Credential $Credential `
                                       -SubscriptionName $SubscriptionName `
                                       -AutomationAccountName $AutomationAccountName

        $AzureAutomationVariables = Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName
        if($AzureAutomationVariables) 
        {
            $AzureAutomationVariables = Group-AssetsByRepository -InputObject $AzureAutomationVariables 
        }

        $RepositoryAssets = Get-GitRepositoryAssetName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.GlobalsFolder)"

        if($AzureAutomationVariables."$RepositoryName")
        {
            $VariableDifferences = Compare-Object -ReferenceObject $AzureAutomationVariables."$RepositoryName".Name `
                                                  -DifferenceObject $RepositoryAssets.Variable
            Foreach($Difference in $VariableDifferences)
            {
                Try
                {
                    if($Difference.SideIndicator -eq '<=')
                    {
                        Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                        Remove-AzureAutomationVariable -Name $Difference.InputObject `
                                                       -AutomationAccountName $AutomationAccountName `
                                                       -Force
                        Write-Verbose -Message "[$($Difference.InputObject)] Removed from Azure Automation"
                    }
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveAAAssetFailure' `
                                                -Message 'Failed to remove an AA Asset' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString $_) ;
                        'AssetName' = $Difference.InputObject ;
                        'AssetType' = 'Variable' ;
                        'AutomationAccountName' = $AutomationAccountName ;
                        'RepositoryName' = $RepositoryName ;
                    }
                    Write-Warning -Message $Exception -WarningAction Continue
                }
            }
        }
        else
        {
            Write-Warning -Message "[$RepositoryName] No Variables found in environment for this repository" `
                          -WarningAction Continue
        }

        $AzureAutomationSchedules = Get-AzureAutomationSchedule -AutomationAccountName $AutomationAccountName
        if($AzureAutomationSchedules) 
        {
            $AzureAutomationSchedules = Group-AssetsByRepository -InputObject $AzureAutomationSchedules 
        }

        if($AzureAutomationSchedules."$RepositoryName")
        {
            $ScheduleDifferences = Compare-Object -ReferenceObject $AzureAutomationSchedules."$RepositoryName".Name `
                                                  -DifferenceObject $RepositoryAssets.Schedule
            Foreach($Difference in $ScheduleDifferences)
            {
                Try
                {
                    if($Difference.SideIndicator -eq '<=')
                    {
                        Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                        Remove-AzureAutomationSchedule -Name $Difference.InputObject `
                                                       -AutomationAccountName $AutomationAccountName `
                                                       -Force
                        Write-Verbose -Message "[$($Difference.InputObject)] Removed from Azure Automation"
                    }
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveAAAssetFailure' `
                                                -Message 'Failed to remove an AA Asset' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString $_) ;
                        'AssetName' = $Difference.InputObject ;
                        'AssetType' = 'Schedule' ;
                        'AutomationAccountName' = $AutomationAccountName ;
                        'RepositoryName' = $RepositoryName ;
                    }
                    Write-Warning -Message $Exception -WarningAction Continue
                }
            }
        }
        else
        {
            Write-Warning -Message "[$RepositoryName] No Schedules found in environment for this repository" `
                          -WarningAction Continue
        }
    }
    Catch
    {
        $Exception = New-Exception -Type 'RemoveAzureAutomationOrphanAssetWorkflowFailure' `
                                   -Message 'Unexpected error encountered in the Remove-AzureAutomationOrphanAsset workflow' `
                                   -Property @{
            'ErrorMessage' = (Convert-ExceptionToString $_) ;
            'RepositoryName' = $RepositoryName ;
        }
        Write-Exception -Exception $Exception -Stream Warning
    }
    Write-Verbose -Message 'Finished [Remove-AzureAutomationOrphanAsset]'
}

<#
    .Synopsis
        Checks an Azure Automation environment and removes any runbooks tagged
        with the current repository that are no longer found in
        the repository

    .Parameter RepositoryName
        The name of the repository
#>
Function Remove-AzureAutomationOrphanRunbook
{
    Param(
        [Parameter(Mandatory = $True)]
        [String]
        $RepositoryName,

        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $True)]
        [String]
        $AutomationAccountName,

        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [PSCustomObject] 
        $RepositoryInformation
    )

    Write-Verbose -Message 'Starting [Remove-AzureAutomationOrphanRunbook]'
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Try
    {
        Connect-AzureAutomationAccount -Credential $Credential `
                                       -SubscriptionName $SubscriptionName `
                                       -AutomationAccountName $AutomationAccountName

        $AzureAutomationRunbooks = Get-AzureAutomationRunbook -AutomationAccountName $AutomationAccountName
        if($AzureAutomationRunbooks) 
        {
            $AzureAutomationRunbooks = Group-RunbooksByRepository -InputObject $AzureAutomationRunbooks 
        }

        $RepositoryWorkflows = Get-GitRepositoryWorkflowName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.RunbookFolder)"
        $Differences = Compare-Object -ReferenceObject $AzureAutomationRunbooks.$RepositoryName.Name `
                                      -DifferenceObject $RepositoryWorkflows
    
        Foreach($Difference in $Differences)
        {
            if($Difference.SideIndicator -eq '<=')
            {
                Try
                {
                    Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                    Remove-AzureAutomationRunbook -Name $Difference.InputObject `
                                                  -AutomationAccountName $AutomationAccountName
                    Write-Verbose -Message "[$($Difference.InputObject)] Removed from Azure Automation"
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveAzureAutomationRunbookFailure' `
                                                -Message 'Failed to remove a Azure Automation Runbook' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString $_) ;
                        'Name' = $Difference.InputObject ;
                        'AutomationAccount' = $AutomationAccountName ;
                    }
                    Write-Warning -Message $Exception -WarningAction Continue
                }
            }
        }
    }
    Catch
    {
        $Exception = New-Exception -Type 'RemoveAzureAutomationOrphanRunbookWorkflowFailure' `
                                   -Message 'Unexpected error encountered in the Remove-AzureAutomationOrphanRunbook workflow' `
                                   -Property @{
            'ErrorMessage' = (Convert-ExceptionToString $_) ;
            'RepositoryName' = $RepositoryName ;
        }
        Write-Exception -Exception $Exception -Stream Warning
    }
    Write-Verbose -Message 'Finished [Remove-AzureAutomationOrphanRunbook]'
}

<#
    .SYNOPSIS
    Returns $true if working in a local development environment, $false otherwise.
#>
function Test-LocalDevelopment
{
    $LocalDevModule = Get-Module -ListAvailable -Name 'LocalDev' -Verbose:$False -ErrorAction 'SilentlyContinue' -WarningAction 'SilentlyContinue'
    if($Null -ne $LocalDevModule -and ($env:LocalAuthoring -ne $False))
    {
        return $True
    }
    return $False
}

<#
.SYNOPSIS
    Gets one or more automation variable values from the given web service endpoint.

.DESCRIPTION
    Get-BatchAutomationVariable gets the value of each variable given in $Name.
    If $Prefix is set, "$Prefix-$Name" is looked up in (helps keep the
    list of variables in $Name concise).

.PARAMETER Name
    A list of variable values to retrieve.
    
.PARAMETER Prefix
    A prefix to be applied to each variable name when performing the lookup. 
    A '-' is added to the end of $Prefix automatically.
#>
Function Get-BatchAutomationVariable
{
    [OutputType([hashtable])]
    Param(
        [Parameter(Mandatory = $True)]
        [String[]]
        $Name,

        [Parameter(Mandatory = $False)]
        [AllowNull()]
        [String]
        $Prefix = $Null
    )
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $Variables = @{}
    
    ForEach($VarName in $Name)
    {
        If(-not [String]::IsNullOrEmpty($Prefix))
        {
            $_VarName =  "$Prefix-$VarName"
        }
        Else
        {
            $_VarName = $VarName
        }
        $Result = Get-AutomationVariable -Name "$_VarName"
        $Variables[$VarName] = $Result
        Write-Verbose -Message "Variable [$Prefix / $VarName] = [$($Variables[$VarName])]"
    }
    Return ($Variables -as [hashtable])
}
<#
.Synopsis
    Returns a list of the runbook workers in the target hybrid runbook worker deployment.
#>
Function Get-AzureAutomationHybridRunbookWorker
{
    Param(
        [Parameter(Mandatory = $True)]
        [String[]]
        $Name
    )
    
    Return @($env:COMPUTERNAME) -as [array]
}

<#
.Synopsis
    Connects to an Azure Automation Account
#>
Function Connect-AzureAutomationAccount
{
    Param(
        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $True)]
        [string]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [string]
        $AutomationAccountName
    )

    $VBP = $VerbosePreference
    $VerbosePreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
    $AzureAccount = Get-AzureAccount
    if($AzureAccount.Id -ne $Credential.UserName)
    {
        $AzureAccount | ForEach-Object { Remove-AzureAccount -Name $_.Id -Force }
        Add-AzureAccount -Credential $Credential
        
    }
    Select-AzureSubscription -SubscriptionName $SubscriptionName
    $AzureAccountAccessible = (Get-AzureAutomationAccount -Name $AutomationAccountName) -as [bool]
    $VerbosePreference = [System.Management.Automation.ActionPreference]$VBP
    if(-not $AzureAccountAccessible)
    {
        Throw-Exception -Type 'AzureAutomationAccountNotAccessible' `
                        -Message 'Could not access the target Azure Automation Account' `
                        -Property @{
                            'Credential' = $Credential ;
                            'SubscriptionName' = $SubscriptionName ;
                            'AutomationAccountName' = $AutomationAccountName ;
                        }
    }
}

<#
.Synopsis
    Top level function for syncing a target git Repository to Azure Automation
#>
Function Sync-GitRepositoryToAzureAutomation
{
    Param(
        [Parameter(Mandatory = $True)]
        [pscredential]
        $SubscriptionAccessCredential,

        [Parameter(Mandatory = $True)]
        [pscredential]
        $RunbookWorkerAccessCredenial,

        [Parameter(Mandatory = $True)]
        [psobject]
        $RepositoryInformation,
        
        [Parameter(Mandatory = $True)]
        [string]
        $RepositoryInformationJSON,

        [Parameter(Mandatory = $True)]
        [string]
        $AutomationAccountName,
        
        [Parameter(Mandatory = $True)]
        [string]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [string]
        $RepositoryName
    )
    
    Write-Verbose -Message 'Starting [Sync-GitRepositoryToAzureAutomation]'
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    
    Try
    {
        $RunbookWorker = Get-AzureAutomationHybridRunbookWorker -Name $RepositoryInformation.HybridWorkerGroup
        
        # Update the repository on all SMA Workers
        Invoke-Command -ComputerName $RunbookWorker -Credential $RunbookWorkerAccessCredenial -ScriptBlock {
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                    
            $RepositoryInformation = $Using:RepositoryInformation
            Update-GitRepository -RepositoryInformation $RepositoryInformation
        }

        $RepositoryChangeJSON = Find-GitRepositoryChange -RepositoryInformation $RepositoryInformation
        $RepositoryChange = ConvertFrom-Json -InputObject $RepositoryChangeJSON
        if($RepositoryChange.CurrentCommit -as [string] -ne $RepositoryInformation.CurrentCommit -as [string])
        {
            Write-Verbose -Message "Processing [$($RepositoryInformation.CurrentCommit)..$($RepositoryChange.CurrentCommit)]"
            Write-Verbose -Message "RepositoryChange [$RepositoryChangeJSON]"
            $ReturnInformationJSON = Group-RepositoryFile -Files $RepositoryChange.Files `
                                                          -RepositoryInformation $RepositoryInformation
            $ReturnInformation = ConvertFrom-Json -InputObject $ReturnInformationJSON
            Write-Verbose -Message "ReturnInformation [$ReturnInformationJSON]"
            
            Foreach($SettingsFilePath in $ReturnInformation.SettingsFiles)
            {
                Publish-AzureAutomationSettingsFileChange -FilePath $SettingsFilePath `
                                                          -CurrentCommit $RepositoryChange.CurrentCommit `
                                                          -RepositoryName $RepositoryName `
                                                          -Credential $SubscriptionAccessCredential `
                                                          -AutomationAccountName $AutomationAccountName `
                                                          -SubscriptionName $SubscriptionName
            }
            Foreach($RunbookFilePath in $ReturnInformation.ScriptFiles)
            {
                Publish-AzureAutomationRunbookChange -FilePath $RunbookFilePath `
                                                     -CurrentCommit $RepositoryChange.CurrentCommit `
                                                     -RepositoryName $RepositoryName `
                                                     -Credential $SubscriptionAccessCredential `
                                                     -AutomationAccountName $AutomationAccountName `
                                                     -SubscriptionName $SubscriptionName
            }
            
            if($ReturnInformation.CleanRunbooks)
            {
                Remove-AzureAutomationOrphanRunbook -RepositoryName $RepositoryName `
                                                    -SubscriptionName $SubscriptionName `
                                                    -AutomationAccountName $AutomationAccountName `
                                                    -Credential $SubscriptionAccessCredential `
                                                    -RepositoryInformation $RepositoryInformation
            }
            if($ReturnInformation.CleanAssets)
            {
                Remove-AzureAutomationOrphanAsset -RepositoryName $RepositoryName `
                                                  -SubscriptionName $SubscriptionName `
                                                  -AutomationAccountName $AutomationAccountName `
                                                  -Credential $SubscriptionAccessCredential `
                                                  -RepositoryInformation $RepositoryInformation
            }
            if($ReturnInformation.ModuleFiles)
            {
                Try
                {
                    Write-Verbose -Message 'Validating Module Path on Runbook Wokers'
                    $RepositoryModulePath = "$($RepositoryInformation.Path)\$($RepositoryInformation.PowerShellModuleFolder)"
                    Invoke-Command -ComputerName $RunbookWorker -Credential $RunbookWorkerAccessCredenial -ScriptBlock {
                        $RepositoryModulePath = $Using:RepositoryModulePath
                        Try
                        {
                            Add-PSEnvironmentPathLocation -Path $RepositoryModulePath
                        }
                        Catch
                        {
                            $Exception = New-Exception -Type 'PowerShellModulePathValidationError' `
                                               -Message 'Failed to set PSModulePath' `
                                               -Property @{
                                'ErrorMessage' = (Convert-ExceptionToString $_) ;
                                'RepositoryModulePath' = $RepositoryModulePath ;
                                'RunbookWorker' = $env:COMPUTERNAME ;
                            }
                            Write-Warning -Message $Exception -WarningAction Continue
                        }
                    }
                    Write-Verbose -Message 'Finished Validating Module Path on Runbook Wokers'
                }
                Catch
                {
                    Write-Exception -Exception $_ -Stream Warning
                }
            }
            $UpdatedRepositoryInformation = (Set-RepositoryInformationCommitVersion -RepositoryInformation $RepositoryInformationJSON `
                                                                                    -RepositoryName $RepositoryName `
                                                                                    -Commit $RepositoryChange.CurrentCommit) -as [string]

            $null = Set-AutomationVariable -Name 'ContinuousIntegration-RepositoryInformation' `
                                           -Value $UpdatedRepositoryInformation

            Write-Verbose -Message "Finished Processing [$($RepositoryInformation.CurrentCommit)..$($RepositoryChange.CurrentCommit)]"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }

    Write-Verbose -Message 'Completed [Sync-GitRepositoryToAzureAutomation]'
}
Export-ModuleMember -Function * -Verbose:$false