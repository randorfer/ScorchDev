#requires -Version 3 -Modules SCOrchDev-Exception, SCOrchDev-GitIntegration, SCOrchDev-Utility
$NunitExe = "$PsScriptRoot\NUnitToHTML\NUnit2Report.Console.exe"
$RepositoryNameRegex = '__RepositoryName:([^;]+);'
$CurrentCommitRegex = 'CurrentCommit:([^;]+);__'

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
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [string]
        $Tenant = $Null
    )
    $CompletedParams = Write-StartingMessage -String $FilePath
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant

        $RunbookInformation = Get-AzureAutomationRunbookInformation -FilePath $FilePath `
                                                                    -RepositoryName $RepositoryName `
                                                                    -Credential $Credential `
                                                                    -AutomationAccountName $AutomationAccountName `
                                                                    -SubscriptionName $SubscriptionName `
                                                                    -ResourceGroupName $ResourceGroupName `
                                                                    -CurrentCommit $CurrentCommit `
                                                                    -Tenant $Tenant
        if($RunbookInformation.Update)
        {
            $UpdateCompleteParams = Write-StartingMessage -CommandName 'Updating Runbook' -String "[$($RunbookInformation | ConvertTo-Json)]"
            if($RunbookInformation.CurrentRunbookType -ne $RunbookInformation.ParameterSet.Type)
            {
                Write-Verbose -Message "Runbook type change from [$($RunbookInformation.CurrentRunbookType)] to [$($RunbookInformation.ParameterSet.Type)]"
                Remove-AzureRmAutomationRunbook -Name $RunbookInformation.ParameterSet.Name `
                                                -ResourceGroupName $RunbookInformation.ParameterSet.ResourceGroupName `
                                                -AutomationAccountName $RunbookInformation.ParameterSet.AutomationAccountName `
                                                -Force
                Write-Verbose -Message 'Old runbook removed'
            }
            $ParameterSet = $RunbookInformation.ParameterSet
            $Null = Import-AzureRmAutomationRunbook @ParameterSet
            Write-CompletedMessage @UpdateCompleteParams
        }
        else
        {
            Write-Verbose -Message "Runbook is not a new version. Skipping. [$($RunbookInformation | ConvertTo-Json)]"
        }
    }
    Catch
    {
        $ErrorActionPreference = 'Stop'
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch ($Exception.FullyQualifiedErrorId)
        {
            Default
            {
                Write-Exception -Stream Warning -Exception $Exception
            }
        }
    }

    Write-CompletedMessage @CompletedParams
}
Function Publish-AzureAutomationPowerShellModule
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
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [string]
        $Tenant = $Null,

        [Parameter(Mandatory = $True)]
        [string]
        $StorageAccountName,

        [Parameter(Mandatory = $False)]
        [string]
        $StorageContainerName = 'omsautomationpsmodules'
    )
    $CompletedParams = Write-StartingMessage -String $FilePath
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant

        $ModuleDefinition = Test-ModuleManifest -Path $FilePath
        if($ModuleDefinition.ModuleBase -notlike "*$($ModuleDefinition.Name)*")
        {
            Throw-Exception -Type 'NestedPSD1' `
                            -Message 'The target PSD1 is not related to the current folder' `
                            -Property @{ 
                                'ModuleBase' = $ModuleDefinition.ModuleBase
                                'Name' = $ModuleDefinition.Name
                            }
        }

        if(Test-AzureAutomationModuleExist -Name $ModuleDefinition.Name `
                                           -ResourceGroupName $ResourceGroupName `
                                           -AutomationAccountName $AutomationAccountName `
                                           -SubscriptionName $SubscriptionName `
                                           -Credential $Credential `
                                           -Tenant $Tenant)
        {
            $AutomationModule = Get-AzureRmAutomationModule -Name $ModuleDefinition.Name `
                                                        -ResourceGroupName $ResourceGroupName `
                                                        -AutomationAccountName $AutomationAccountName
        
            if($AutomationModule.Version -eq $ModuleDefinition.Version)
            {
                Throw-Exception -Type 'ModuleVersionAlreadyImported' `
                                -Message 'This version of the module is already in automation' `
                                -Property @{ 
                                    'Name' = $ModuleDefinition.Name
                                    'AutomationVersion' = $AutomationModule.Version -as [string]
                                    'LocalVersion' = $ModuleDefinition.Version -as [string]
                                }
            }
        }
        else
        {
            Write-Verbose -Message 'New module'
        }
        $TempDirectory = New-TempDirectory

        $ZipFilePath = "$($TempDirectory.FullName)\$($ModuleDefinition.Name).zip"
        New-ZipFile -SourceDir $ModuleDefinition.ModuleBase `
                    -ZipFilePath $ZipFilePath `
                    -OverwriteExisting $True

        $StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
        Try 
        { 
            $StorageContainer = Get-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context
        }
        Catch
        {
            $StorageContainer = New-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -Permission Blob
        }
        $Blob = Set-AzureStorageBlobContent -File $ZipFilePath -Container $StorageContainerName -Context $StorageAccount.Context -Force
        $ContentLink = "$($StorageContainer.CloudBlobContainer.Uri.AbsoluteUri)/$($Blob.Name)"
        $Module = New-AzureRmAutomationModule -Name $ModuleDefinition.Name `
                                              -ContentLink $ContentLink `
                                              -ResourceGroupName $ResourceGroupName `
                                              -AutomationAccountName $AutomationAccountName
        
        Write-Verbose -Message 'Waiting for module to import'
        $TimeoutPeriod = (Get-Date).AddMinutes(15)
        Do
        {
            Start-Sleep -Seconds 5
            $Module = Get-AzureRmAutomationModule -Name $ModuleDefinition.Name `
                                                  -ResourceGroupName $ResourceGroupName `
                                                  -AutomationAccountName $AutomationAccountName
            $Timeout = (Get-Date) -ge $TimeoutPeriod
            Write-Debug -Message "Module Provisioning State [$($Module.ProvisioningState)] : Timeout [$Timeout]"
        }
        While((-not $TimeOut) -and ($Module.ProvisioningState -eq 'Creating' -or $Module.ProvisioningState -eq 'RunningImportModuleRunbook'))
        Write-Verbose -Message "Module Imported. Provisioning State [$($Module.ProvisioningState)]"
    }
    Catch
    {
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch ($Exception.FullyQualifiedErrorId)
        {
            Default
            {
                Write-Exception -Stream Warning -Exception $Exception
            }
        }
    }
    Finally
    {
        if($TempDirectory -as [bool])
        {
            if(Test-Path $TempDirectory.FullName)
            {
                Remove-Item -Path $TempDirectory.FullName -Force -Recurse
            }
        }
    }

    Write-CompletedMessage @CompletedParams
}
Function Publish-AzureAutomationDSCChange
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
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [string]
        $Tenant = $Null
    )
    $CompletedParams = Write-StartingMessage -String $FilePath
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        if($FilePath -like '*.tests.ps1')
        {
            Throw-Exception -Type 'PesterTestFile' -Message 'This file is a pester test file. Do not publish.'
        }
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant

        $DSCInformation = Get-AzureAutomationDSCInformation -FilePath $FilePath `
                                                            -RepositoryName $RepositoryName `
                                                            -Credential $Credential `
                                                            -AutomationAccountName $AutomationAccountName `
                                                            -SubscriptionName $SubscriptionName `
                                                            -ResourceGroupName $ResourceGroupName `
                                                            -CurrentCommit $CurrentCommit `
                                                            -Tenant $Tenant
        if($DSCInformation.Update)
        {
            $UpdateCompleteParams = Write-StartingMessage -CommandName 'Updating DSC Configuration' -String "[$($DSCInformation | ConvertTo-Json -Depth ([int]::MaxValue))]"
            $ParameterSet = $DSCInformation.ParameterSet
            $Null = Import-AzureRmAutomationDscConfiguration @ParameterSet

            if($DSCInformation.ConfigurationData -as [bool])
            {
                $Null = Start-AzureRmAutomationDscCompilationJob `
                    -ResourceGroupName $ResourceGroupName `
                    -AutomationAccountName $AutomationAccountName `
                    -ConfigurationName $DSCInformation.ConfigurationName `
                    -ConfigurationData $DSCInformation.ConfigurationData
            }
            else
            {
                $Null = Start-AzureRmAutomationDscCompilationJob `
                    -ResourceGroupName $ResourceGroupName `
                    -AutomationAccountName $AutomationAccountName `
                    -ConfigurationName $DSCInformation.ConfigurationName
            }

            Write-CompletedMessage @UpdateCompleteParams
        }
        else
        {
            Write-Verbose -Message "DSC Configuration is not a new version. Skipping. [$($DSCInformation | ConvertTo-Json -Depth ([int]::MaxValue))]"
        }
    }
    Catch
    {
        $ErrorActionPreference = 'Stop'
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch ($Exception.FullyQualifiedErrorId)
        {
            Default
            {
                Write-Exception -Stream Warning -Exception $Exception
            }
        }
    }

    Write-CompletedMessage @CompletedParams
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
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [string]
        $Tenant = $Null
    )
    
    $CompletedParams = Write-StartingMessage -String $FilePath
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant

        $Variables = Get-GlobalFromFile -FilePath $FilePath -GlobalType Variables        
        foreach($VariableName in $Variables.Keys)
        {
            $VariableCompletedParams = Write-StartingMessage -CommandName 'Publish Variable' -String $VariableName
            Try
            {
                $Variable = $Variables.$VariableName
                $VariableInformation = Get-AzureAutomationGlobalInformation -Name $VariableName `
                                                                            -RepositoryName $RepositoryName `
                                                                            -Credential $Credential `
                                                                            -AutomationAccountName $AutomationAccountName `
                                                                            -SubscriptionName $SubscriptionName `
                                                                            -ResourceGroupName $ResourceGroupName `
                                                                            -CurrentCommit $CurrentCommit `
                                                                            -Type Variable
                if($VariableInformation.Update)
                {
                    Write-Verbose -Message "New version for $VariableName"
                    $DescriptionParameterSet = $VariableInformation.ParameterSet.Clone()
                    $ValueParameterSet = $VariableInformation.ParameterSet.Clone()
                    $Null = $ValueParameterSet.Remove('Description')
                    $ValueParameterSet.Encrypted = $Variable.isEncrypted
                    $ValueParameterSet.Value = $Variable.Value

                    $Command = $VariableInformation.Command 
                    $null = & $Command @ValueParameterSet
                    $null = Set-AzureRmAutomationVariable @DescriptionParameterSet
                }
                else
                {
                    Write-Debug -Message "No new version for $VariableName"
                }
            }
            Catch
            {
                $Exception = $_
                $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
                Switch ($ExceptionInfo.FullyQualifiedErrorId)
                {
                    Default
                    {
                        Write-Exception -Exception $Exception -Stream Warning
                    }
                }
            }
            Write-CompletedMessage @VariableCompletedParams
        }
        $Schedules = Get-GlobalFromFile -FilePath $FilePath -GlobalType Schedules
        foreach($ScheduleName in $Schedules.Keys)
        {
            $ScheduleCompletedParams = Write-StartingMessage -CommandName 'Publish Schedule' -String $ScheduleName
            try
            {
                $Schedule = $Schedules."$ScheduleName"
                
                $ScheduleInformation = Get-AzureAutomationGlobalInformation -Name $ScheduleName `
                                                                            -RepositoryName $RepositoryName `
                                                                            -Credential $Credential `
                                                                            -AutomationAccountName $AutomationAccountName `
                                                                            -SubscriptionName $SubscriptionName `
                                                                            -ResourceGroupName $ResourceGroupName `
                                                                            -CurrentCommit $CurrentCommit `
                                                                            -Type Schedule
                if($ScheduleInformation.Update)
                {
                    if($ScheduleInformation.Command -eq 'UpdateSchedule')
                    {
                        # A schedule update is a schedule delete and re-create
                        Write-Verbose -Message "[$($ScheduleName)] is an Updated Schedule. Deleting to re-create"
                        Remove-AzureRmAutomationSchedule -Name $ScheduleName `
                                                         -Force `
                                                         -AutomationAccountName $AutomationAccountName `
                                                         -ResourceGroupName $ResourceGroupName
                    }
                    $CreateSchedule = New-AzureRmAutomationSchedule -Name $ScheduleName `
                                                                    -Description $ScheduleDescription `
                                                                    -DayInterval $Schedule.DayInterval `
                                                                    -StartTime $Schedule.NextRun `
                                                                    -ExpiryTime $Schedule.ExpirationTime `
                                                                    -AutomationAccountName $AutomationAccountName `
                                                                    -ResourceGroupName $ResourceGroupName
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
                    $Parameters = ConvertFrom-PSCustomObject -InputObject $Schedule.Parameter `
                                                          -MemberType NoteProperty
                    $Register = Register-AzureRmAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName `
                                                                            -RunbookName $Schedule.RunbookName `
                                                                            -ScheduleName $ScheduleName `
                                                                            -Parameters $Parameters `
                                                                            -ResourceGroupName $ResourceGroupName
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
                else
                {
                    Write-Debug -Message "No new version for $ScheduleName"
                }
            }
            Catch
            {
                Write-Exception -Exception $_ -Stream Warning
                Remove-AzureRmAutomationSchedule -Name $ScheduleName `
                                                 -Force `
                                                 -AutomationAccountName $AutomationAccountName `
                                                 -ResourceGroupName $ResourceGroupName
            }
            Write-CompletedMessage @ScheduleCompletedParams
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-CompletedMessage @CompletedParams
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
        $ResourceGroupName,

        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [PSCustomObject] 
        $RepositoryInformation,

        [Parameter(Mandatory = $False)]
        [string]
        $Tenant = $Null
    )

    $CompletedParams = Write-StartingMessage
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant

        $AzureAutomationVariables = Get-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName `
                                                                  -ResourceGroupName $ResourceGroupName
        if($AzureAutomationVariables) 
        {
            $AzureAutomationVariables = Group-AutomationAssetByDescriptionRepository -InputObject $AzureAutomationVariables 
        }

        $RepositoryAssets = Get-GitRepositoryAssetName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.GlobalsFolder)"

        if($AzureAutomationVariables."$RepositoryName" -as [bool])
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
                        Remove-AzureRmAutomationVariable -Name $Difference.InputObject `
                                                         -AutomationAccountName $AutomationAccountName `
                                                         -ResourceGroupName $ResourceGroupName `
                                                         -Force
                        Write-Verbose -Message "[$($Difference.InputObject)] Removed from Azure Automation"
                    }
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveAzureAutomationAssetFailure' `
                                                -Message 'Failed to remove an Azure Automation Asset' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
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
            Write-Verbose -Message "[$RepositoryName] No Variables found in environment for this repository"
        }

        $AzureAutomationSchedules = Get-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName `
                                                                  -ResourceGroupName $ResourceGroupName
        if($AzureAutomationSchedules) 
        {
            $AzureAutomationSchedules = Group-AutomationAssetByDescriptionRepository -InputObject $AzureAutomationSchedules 
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
                        Remove-AzureRmAutomationSchedule -Name $Difference.InputObject `
                                                         -AutomationAccountName $AutomationAccountName `
                                                         -ResourceGroupName $ResourceGroupName `
                                                         -Force
                        Write-Verbose -Message "[$($Difference.InputObject)] Removed from Azure Automation"
                    }
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveAzureAutomationAssetFailure' `
                                                -Message 'Failed to remove an Azure Automation Asset' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
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
            Write-Verbose -Message "[$RepositoryName] No Schedules found in environment for this repository"
        }
    }
    Catch
    {
        $Exception = New-Exception -Type 'RemoveAzureAutomationOrphanAssetWorkflowFailure' `
                                   -Message 'Unexpected error encountered in the Remove-AzureAutomationOrphanAsset workflow' `
                                   -Property @{
            'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
            'RepositoryName' = $RepositoryName ;
        }
        Write-Exception -Exception $Exception -Stream Warning
    }
    Write-CompletedMessage @CompletedParams
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
        $ResourceGroupName,

        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [PSCustomObject] 
        $RepositoryInformation,

        [Parameter(Mandatory = $False)]
        [string]
        $Tenant = $Null
    )

    $CompletedParams = Write-StartingMessage
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant

        $AzureAutomationRunbook = Get-AzureRmAutomationRunbook -AutomationAccountName $AutomationAccountName `
                                                                -ResourceGroupName $ResourceGroupName
        $AzureAutomationRunbook = $AzureAutomationRunbook | ForEach-Object { 
            Get-AzureRmAutomationRunbook -Name $_.Name `
                                         -AutomationAccountName $_.AutomationAccountName `
                                         -ResourceGroupName $_.ResourceGroupName 
        }
        if($AzureAutomationRunbook) 
        {
            $AzureAutomationRunbook = Group-AutomationAssetByTaggedRepository -InputObject $AzureAutomationRunbook 
        }

        $RepositoryWorkflows = Get-GitRepositoryRunbookName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.RunbookFolder)"
        $Differences = Compare-Object -ReferenceObject $AzureAutomationRunbook.$RepositoryName.Name `
                                      -DifferenceObject $RepositoryWorkflows
    
        Foreach($Difference in $Differences)
        {
            if($Difference.SideIndicator -eq '<=')
            {
                Try
                {
                    Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                    Remove-AzureRmAutomationRunbook -Name $Difference.InputObject `
                                                    -AutomationAccountName $AutomationAccountName `
                                                    -ResourceGroupName $ResourceGroupName `
                                                    -Force
                    Write-Verbose -Message "[$($Difference.InputObject)] Removed from Azure Automation"
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveAzureAutomationRunbookFailure' `
                                                -Message 'Failed to remove a Azure Automation Runbook' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
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
            'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
            'RepositoryName' = $RepositoryName ;
        }
        Write-Exception -Exception $Exception -Stream Warning
    }
    Write-CompletedMessage @CompletedParams
}

<#
    .Synopsis
        Checks an Azure Automation environment and removes any DSC tagged
        with the current repository that are no longer found in
        the repository

    .Parameter RepositoryName
        The name of the repository
#>
Function Remove-AzureAutomationOrphanDSC
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
        $ResourceGroupName,

        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [PSCustomObject] 
        $RepositoryInformation,

        [Parameter(Mandatory = $False)]
        [string]
        $Tenant = $Null
    )

    $CompletedParams = Write-StartingMessage
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant

        $AzureAutomationDSCConfiguration = (Get-AzureRmAutomationDscConfiguration -ResourceGroupName $ResourceGroupName `
                                                                                  -AutomationAccountName $AutomationAccountName).Name

        $DSCConfiguration = Get-GitRepositoryDSCInformation -Path "$($RepositoryInformation.Path)\..\"

        $DSCConfigurationDifferences = Compare-Object -ReferenceObject ($AzureAutomationDSCConfiguration -as [string[]]) `
                                                          -DifferenceObject ($DSCNodeConfiguration  -as [string[]])
        Foreach($Difference in $DSCConfigurationDifferences)
        {
            Try
            {
                if($Difference.SideIndicator -eq '<=')
                {
                    Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                    $NodeConfiguration = Get-AzureRmAutomationDscNodeConfiguration -ConfigurationName $Difference.InputObject `
                                                                                   -ResourceGroupName $ResourceGroupName `
                                                                                   -AutomationAccountName $AutomationAccountName
                    foreach($_NodeConfiguration in $NodeConfiguration)
                    {
                        Write-Verbose -Message "Removing Node Configuration [$($_NodeConfiguration.Name)]"
                        $Null = Remove-AzureRmAutomationDscNodeConfiguration -Name $_NodeConfiguration.Name `
                                                                             -ResourceGroupName $ResourceGroupName `
                                                                             -AutomationAccountName $AutomationAccountName `
                                                                             -IgnoreNodeMappings `
                                                                             -Force
                    }
                    $Null = Remove-AzureRmAutomationDscConfiguration -Name $Difference.InputObject `
                                                                     -AutomationAccountName $AutomationAccountName `
                                                                     -ResourceGroupName $ResourceGroupName `
                                                                     -Force
                    Write-Verbose -Message "[$($Difference.InputObject)] Removed from Azure Automation"
                }
            }
            Catch
            {
                $Exception = New-Exception -Type 'RemoveAzureAutomationDSCConfigurationFailure' `
                                            -Message 'Failed to remove an Azure Automation DSC Configuration' `
                                            -Property @{
                    'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
                    'AssetName' = $Difference.InputObject ;
                    'AssetType' = 'Variable' ;
                    'AutomationAccountName' = $AutomationAccountName ;
                    'RepositoryName' = $RepositoryName ;
                }
                Write-Warning -Message $Exception -WarningAction Continue
            }
        }
    }
    Catch
    {
        $Exception = New-Exception -Type 'RemoveAzureAutomationOrphanDSCFailure' `
                                   -Message 'Unexpected error encountered in the Remove-AzureAutomationOrphanDSC' `
                                   -Property @{
            'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
            'RepositoryName' = $RepositoryName ;
        }
        Write-Exception -Exception $Exception -Stream Warning
    }
    Write-CompletedMessage @CompletedParams
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
    $CompletedParams = Write-StartingMessage -Stream Debug
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
    Write-CompletedMessage @CompletedParams
    Return ($Variables -as [hashtable])
}
<#
.Synopsis
    Returns a list of the runbook workers in the target hybrid runbook worker deployment.
#>
Function Get-AzureAutomationHybridRunbookWorker
{
    Param(
        [Parameter(Mandatory = $False)]
        [String]
        $HybridWorkerGroup
    )
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParams = Write-StartingMessage -String $HybridWorkerGroup
    $Var = Get-BatchAutomationVariable -Name 'HybridRunbookWorker' `
                                       -Prefix 'Global'
    
    $HT = $Var.HybridRunbookWorker | ConvertFrom-JSON

    Write-CompletedMessage @CompletedParams
    Return $HT.$HybridWorkerGroup -as [string[]]
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
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [string]
        $Tenant = $Null,

        [Parameter(Mandatory = $True)]
        [string]
        $StorageAccountName
    )
    
    $CompletedParams = Write-StartingMessage -String $RepositoryName
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $RepositoryInformation = $RepositoryInformationJSON | ConvertFrom-Json | ConvertFrom-PSCustomObject
    Foreach($RepositoryName in $RepositoryInformation.Keys -as [array])
    {
        $_RepositoryInformation = $RepositoryInformation.$RepositoryName
        $RepositoryInformationJSON = Sync-IndividualGitRepositoryToAzureAutomation -RepositoryInformation $_RepositoryInformation `
                                                                                   -RepositoryName $RepositoryName `
                                                                                   -RepositoryInformationJSON $RepositoryInformationJSON `
                                                                                   -SubscriptionAccessCredential $SubscriptionAccessCredential `
                                                                                   -RunbookWorkerAccessCredenial $RunbookWorkerAccessCredenial `
                                                                                   -AutomationAccountName $AutomationAccountName `
                                                                                   -SubscriptionName $SubscriptionName `
                                                                                   -ResourceGroupName $ResourceGroupName `
                                                                                   -Tenant $Tenant `
                                                                                   -StorageAccountName $StorageAccountName
    }

    Write-CompletedMessage @CompletedParams
    Return (Select-FirstValid -Value @($UpdatedRepositoryInformation, $RepositoryInformationJSON))
}
<#
#>
Function Sync-IndividualGitRepositoryToAzureAutomation
{
    Param(
        [Parameter(Mandatory = $True)]
        [pscredential]
        $SubscriptionAccessCredential,

        [Parameter(Mandatory = $True)]
        [pscredential]
        $RunbookWorkerAccessCredenial,
        
        [Parameter(Mandatory = $True)]
        $RepositoryInformation,

        [Parameter(Mandatory = $True)]
        [string]
        $RepositoryInformationJSON,

        [Parameter(Mandatory = $True)]
        [string]
        $RepositoryName,

        [Parameter(Mandatory = $True)]
        [string]
        $AutomationAccountName,
        
        [Parameter(Mandatory = $True)]
        [string]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [string]
        $Tenant = $Null,

        [Parameter(Mandatory = $True)]
        [string]
        $StorageAccountName
    )
    
    $CompletedParams = Write-StartingMessage -String "[$RepositoryName] $(ConvertTo-Json -InputObject $RepositoryInformation)"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        $RunbookWorker = Get-AzureAutomationHybridRunbookWorker -HybridWorkerGroup $RepositoryInformation.HybridWorkerGroup
        # Update the repository on all Workers
        Invoke-Command -ComputerName $RunbookWorker -Credential $RunbookWorkerAccessCredenial -ScriptBlock {
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                    
            $RepositoryInformation = $Using:RepositoryInformation
            Update-GitRepository -RepositoryPath $RepositoryInformation.RepositoryPath `
                                    -Path $RepositoryInformation.Path `
                                    -Branch $RepositoryInformation.Branch
        }
        $RepositoryChange = Find-GitRepositoryChange -Path $RepositoryInformation.Path `
                                                     -StartCommit $RepositoryInformation.CurrentCommit
            
        if(-not ($RepositoryChange.CurrentCommit -as [string]).Equals($RepositoryInformation.CurrentCommit -as [string]))
        {
            Write-Verbose -Message "Processing [$($RepositoryInformation.CurrentCommit)..$($RepositoryChange.CurrentCommit)]"
            Write-Verbose -Message "RepositoryChange [$($RepositoryChange | ConvertTo-Json)]"
            $ReturnInformation = Group-RepositoryFile -File $RepositoryChange.Files `
                                                        -Path $_RepositoryInformation.Path `
                                                        -RunbookFolder $RepositoryInformation.RunbookFolder `
                                                        -GlobalsFolder $RepositoryInformation.GlobalsFolder `
                                                        -PowerShellModuleFolder $RepositoryInformation.PowerShellModuleFolder `
                                                        -DSCFolder $RepositoryInformation.DSCFolder

            Foreach($SettingsFilePath in $ReturnInformation.SettingsFiles)
            {
                Publish-AzureAutomationSettingsFileChange -FilePath $SettingsFilePath `
                                                          -CurrentCommit $RepositoryChange.CurrentCommit `
                                                          -RepositoryName $RepositoryName `
                                                          -Credential $SubscriptionAccessCredential `
                                                          -AutomationAccountName $AutomationAccountName `
                                                          -SubscriptionName $SubscriptionName `
                                                          -ResourceGroupName $ResourceGroupName `
                                                          -Tenant $Tenant
            }

            Foreach($ModuleFilePath in $ReturnInformation.ModuleFiles)
            {
                Publish-AzureAutomationPowerShellModule -FilePath $ModuleFilePath `
                                                        -StorageAccountName $StorageAccountName `
                                                        -CurrentCommit $RepositoryChange.CurrentCommit `
                                                        -RepositoryName $RepositoryName `
                                                        -Credential $SubscriptionAccessCredential `
                                                        -AutomationAccountName $AutomationAccountName `
                                                        -SubscriptionName $SubscriptionName `
                                                        -ResourceGroupName $ResourceGroupName `
                                                        -Tenant $Tenant
            }

            Foreach($RunbookFilePath in $ReturnInformation.ScriptFiles)
            {
                Publish-AzureAutomationRunbookChange -FilePath $RunbookFilePath `
                                                     -CurrentCommit $RepositoryChange.CurrentCommit `
                                                     -RepositoryName $RepositoryName `
                                                     -Credential $SubscriptionAccessCredential `
                                                     -AutomationAccountName $AutomationAccountName `
                                                     -SubscriptionName $SubscriptionName `
                                                     -ResourceGroupName $ResourceGroupName `
                                                     -Tenant $Tenant
            }
            Foreach($DSCFilePath in $ReturnInformation.DSCFiles)
            {
                Publish-AzureAutomationDSCChange -FilePath $DSCFilePath `
                                                 -CurrentCommit $RepositoryChange.CurrentCommit `
                                                 -RepositoryName $RepositoryName `
                                                 -Credential $SubscriptionAccessCredential `
                                                 -AutomationAccountName $AutomationAccountName `
                                                 -SubscriptionName $SubscriptionName `
                                                 -ResourceGroupName $ResourceGroupName `
                                                 -Tenant $Tenant
            }

            if($ReturnInformation.CleanRunbooks)
            {
                Remove-AzureAutomationOrphanRunbook -RepositoryName $RepositoryName `
                                                    -Credential $SubscriptionAccessCredential `
                                                    -AutomationAccountName $AutomationAccountName `
                                                    -ResourceGroupName $ResourceGroupName `
                                                    -SubscriptionName $SubscriptionName `
                                                    -RepositoryInformation $RepositoryInformation `
                                                    -Tenant $Tenant
            }
            if($ReturnInformation.CleanAssets)
            {
                Remove-AzureAutomationOrphanAsset -RepositoryName $RepositoryName `
                                                  -Credential $SubscriptionAccessCredential `
                                                  -AutomationAccountName $AutomationAccountName `
                                                  -ResourceGroupName $ResourceGroupName `
                                                  -SubscriptionName $SubscriptionName `
                                                  -RepositoryInformation $RepositoryInformation `
                                                  -Tenant $Tenant
            }
            if($ReturnInformation.CleanDSC)
            {
                Remove-AzureAutomationOrphanDSC -RepositoryName $RepositoryName `
                                                -Credential $SubscriptionAccessCredential `
                                                -AutomationAccountName $AutomationAccountName `
                                                -ResourceGroupName $ResourceGroupName `
                                                -SubscriptionName $SubscriptionName `
                                                -RepositoryInformation $RepositoryInformation `
                                                -Tenant $Tenant
            }

            $UpdatedRepositoryInformation = (Update-RepositoryInformationCommitVersion -RepositoryInformationJSON $RepositoryInformationJSON `
                                                                                        -RepositoryName $RepositoryName `
                                                                                        -Commit $RepositoryChange.CurrentCommit) -as [string]

            Write-Verbose -Message "Finished Processing [$($_RepositoryInformation.CurrentCommit)..$($RepositoryChange.CurrentCommit)]"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }

    Write-CompletedMessage @CompletedParams
    Return (Select-FirstValid -Value @($UpdatedRepositoryInformation, $RepositoryInformationJSON))
}
<#
    .Synopsis
        Invokes test suites on the Runbooks and PowerShell modules
#>
Function Invoke-IntegrationTest
{
    Param(
        [Parameter(
            Mandatory = $True,
            Position = 0,
            ValueFromPipeline = $True
        )]
        [string[]]
        $Path
    )
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParams = Write-StartingMessage -String $($Path -join ';')
    $Result = @{}
    Try
    {
        if((Get-Module -Name Pester -ListAvailable) -as [bool])
        {
            $TempDirectory = New-TempDirectory
            Try
            {
                Foreach($_Path in $Path)
                {
                    Write-Verbose -Message $_Path
                    $Item = Get-Item -Path $_Path
                    if(-not ($item.PSIsContainer))
                    {
                        $Item = $Item.Directory
                    }
                    $TestFiles = Get-ChildItem -Path $Item.FullName -Include *.tests.ps1 -Recurse
                    
                    if($TestFiles -as [bool])
                    {
                        $ReportPath = "$TempDirectory\$($Item.Name).xml"
                        Invoke-Pester $Item.FullName -OutputFile $ReportPath -OutputFormat NUnitXml -Quiet
                    }
                }
                $CurrentDirectory = $PWD
                Try
                {
                    Set-Location -Path "$PsScriptRoot\NUnitToHTML"
                    $XMLFiles = Get-ChildItem -Path $TempDirectory -Filter *.xml
                    foreach($XMLFile in $XMLFiles)
                    {
                        $OutputFile = "$($TempDirectory.FullName)\$($XmlFile.Name)"
                        Write-Verbose -Message "$NunitEXE --fileset='$($XMLFile.FullName)' -o $OutputFile"
                        Invoke-Expression -Command "$NunitEXE --fileset='$($XMLFile.FullName)' -o $($TempDirectory.FullName)\$($XmlFile.Name)"
                        $Null = $Result.Add($XmlFile.Name, ((Get-Content $OutputFile) -as [string]))
                    }
                }
                Finally
                {
                    Set-Location $PWD
                }
            }
            Finally
            {
              Remove-Item -Path $TempDirectory -Force -Recurse
            }
            
        }
        <#
        if((Get-Module -Name PSScriptAnalyzer -ListAvailable) -as [bool])
        {
            $Result.PSScriptAnalyzer = New-Object -TypeName System.Collections.ArrayList
            $ChildItem = Get-ChildItem -Path $Path -Recurse -Include *.ps1,*.psm1 -Exclude *.tests.ps1
            $ChildItem | ForEach-Object {
                $AnalyzerResult = Invoke-ScriptAnalyzer -Path $_.FullName
                $Null = $Result.PSScriptAnalyzer.Add(@{'FileName' = $_.FullName ; 'AnalyzerResult' = Select-FirstValid -Value ($AnalyzerResult,'Passing') })
            }
        }#>
    }
    Catch
    {
        Write-Exception -Exception $_ -Stream Warning
    }

    Write-CompletedMessage @CompletedParams
    Return $Result
}
<#
    .Synopsis
        Check to see if the target Configuration already exists in Azure Automation
#>
Function Test-AzureAutomationDSCConfigurationExist
{
    Param(
        [Parameter(Mandatory = $True)]
        [String] 
        $Name,

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
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [String]
        $Tenant = $Null
    )

    $CompletedParams = Write-StartingMessage -String $Name
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant

        $Configuration = Get-AzureRmAutomationDscConfiguration -Name $Name `
                                                               -AutomationAccountName $AutomationAccountName `
                                                               -ResourceGroupName $ResourceGroupName
    }
    Catch
    {
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch ($Exception.FullyQualifiedErrorId)
        {
            'Microsoft.Azure.Commands.Automation.Cmdlet.GetAzureAutomationDscConfiguration'
            {
                $Configuration = $False
            }
            Default
            {
                Write-Exception -Exception $Exception -Stream Warning
                $Configuration = $False
            }
        }
    }

    Write-CompletedMessage @CompletedParams -Status $($Configuration -as [bool])
    return $Configuration -as [bool]
}
<#
    .Synopsis
        Check to see if the target Runbook already exists in Azure Automation
#>
Function Test-AzureAutomationRunbookExist
{
    Param(
        [Parameter(Mandatory = $True)]
        [String] 
        $Name,

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
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [String]
        $Tenant = $Null
    )

    $CompletedParams = Write-StartingMessage -String $Name
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant

        $Runbook = Get-AzureRmAutomationRunbook -Name $Name `
                                                -AutomationAccountName $AutomationAccountName `
                                                -ResourceGroupName $ResourceGroupName
    }
    Catch
    {
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch ($Exception.FullyQualifiedErrorId)
        {
            'Microsoft.Azure.Commands.Automation.Cmdlet.GetAzureAutomationRunbook'
            {
                $Runbook = $False
            }
            Default
            {
                Write-Exception -Exception $Exception -Stream Warning
                $Runbook = $False
            }
        }
    }

    Write-CompletedMessage @CompletedParams
    return $Runbook -as [bool]
}

<#
    .Synopsis
        Check to see if the target Runbook already exists in Azure Automation
#>
Function Test-AzureAutomationModuleExist
{
    Param(
        [Parameter(Mandatory = $True)]
        [String] 
        $Name,

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
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [String]
        $Tenant = $Null
    )

    $CompletedParams = Write-StartingMessage -String $Name
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant

        $AutomationModule = Get-AzureRmAutomationModule -Name $ModuleDefinition.Name `
                                                -ResourceGroupName $ResourceGroupName `
                                                -AutomationAccountName $AutomationAccountName
    }
    Catch
    {
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch ($Exception.FullyQualifiedErrorId)
        {
            'Microsoft.Azure.Commands.Automation.Cmdlet.GetAzureAutomationModule'
            {
                $Module = $False
            }
            Default
            {
                Write-Exception -Exception $Exception -Stream Warning
                $Module = $False
            }
        }
    }

    Write-CompletedMessage @CompletedParams
    return $Module -as [bool]
}

Function Test-AzureAutomationGlobalExist
{
    Param(
        [Parameter(Mandatory = $True)]
        [String] 
        $Name,

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
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $True)]
        [String]
        [ValidateSet('Variable','Schedule')]
        $Type,

        [Parameter(Mandatory = $False)]
        [String]
        $Tenant = $Null
    )

    $CompletedParams = Write-StartingMessage -String $Name
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant

        switch($Type)
        {
            'Variable'
            {
                $Global = Get-AzureRmAutomationVariable -Name $Name `
                                                        -AutomationAccountName $AutomationAccountName `
                                                        -ResourceGroupName $ResourceGroupName
            }
            'Schedule'
            {
                $Global = Get-AzureRmAutomationSchedule -Name $Name `
                                                        -AutomationAccountName $AutomationAccountName `
                                                        -ResourceGroupName $ResourceGroupName
            }
        }
        
    }
    Catch
    {
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch ($Exception.FullyQualifiedErrorId)
        {
            'Microsoft.Azure.Commands.Automation.Cmdlet.GetAzureAutomationVariable'
            {
                $Global = $False
            }
            'Microsoft.Azure.Commands.Automation.Cmdlet.GetAzureAutomationSchedule'
            {
                $Global = $False
            }
            Default
            {
                Write-Exception -Exception $Exception -Stream Warning
                $Global = $False
            }
        }
    }

    Write-CompletedMessage @CompletedParams
    return $Global -as [bool]
}
Function Get-AzureAutomationDSCInformation
{
    Param(
        [Parameter(Mandatory = $True)]
        [String] 
        $FilePath,

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
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [String]
        $CurrentCommit = '-1',

        [Parameter(Mandatory = $False)]
        [string]
        $Tenant = $Null
    )

    $CompletedParams = Write-StartingMessage -String $FilePath
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant
        $ConfigurationName = Get-DSCConfigurationName -FilePath $FilePath
        $NodeName = Get-DSCNodeName -FilePath $FilePath
        if($NodeName -as [bool]) 
        {
            $AllNodes = @(
                @{
                    NodeName = '*'
                    PSDscAllowPlainTextPassword = $True
                }
            )
            Foreach($_NodeName in $NodeName)
            {
                $AllNodes += @{'NodeName' = $_NodeName }
            }

            $ConfigurationData = @{
                AllNodes = $AllNodes
            }
        } 
        else
        {
            $ConfigurationData = $Null
        }
        if(Test-AzureAutomationDSCConfigurationExist -Name $ConfigurationName `
                                            -Credential $Credential `
                                            -AutomationAccountName $AutomationAccountName `
                                            -SubscriptionName $SubscriptionName `
                                            -ResourceGroupName $ResourceGroupName `
                                            -Tenant $Tenant)
        {
            $DSCConfiguration = Get-AzureRmAutomationDscConfiguration -Name $ConfigurationName `
                                                                      -ResourceGroupName $ResourceGroupName `
                                                                      -AutomationAccountName $AutomationAccountName

            $Tags = $DSCConfiguration.Tags
            if($Tags.ContainsKey('CurrentCommit')) { $DSCCurrentCommit = $Tags.CurrentCommit }
            else { $DSCCurrentCommit = -1 }
            if($DSCCurrentCommit -ne $CurrentCommit) { $Tags.CurrentCommit = $CurrentCommit ; $Update = $True }
            else { $Update = $False }
            
            $Description = $DSCConfiguration.Description
        }
        else
        {
            $Tags = @{ 
                'RepositoryName' = $RepositoryName
                'CurrentCommit' = $CurrentCommit
            }
            
            $Update = $True
            $Description = [string]::Empty
        }
    }
    Catch
    {
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch ($Exception.FullyQualifiedErrorId)
        {
            Default
            {
                Throw
            }
        }
    }

    Write-CompletedMessage @CompletedParams
    Return @{ 
        'Update' = $Update
        'ConfigurationName' = $ConfigurationName
        'ConfigurationData' = $ConfigurationData
        'ParameterSet' = @{
            'Tags' = $Tags
            'AutomationAccountName' = $AutomationAccountName
            'ResourceGroupName' = $ResourceGroupName
            'SourcePath' = $FilePath
            'Description' = $Description
            'Force' = $True
            'Published' = $True
        }
    }
}
Function Get-AzureAutomationRunbookInformation
{
    Param(
        [Parameter(Mandatory = $True)]
        [String] 
        $FilePath,

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
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [String]
        $CurrentCommit = '-1',

        [Parameter(Mandatory = $False)]
        [string]
        $Tenant = $Null
    )

    $CompletedParams = Write-StartingMessage -String $FilePath
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant
        
        if(Test-FileIsWorkflow -FilePath $FilePath)
        {
            $Name = Get-WorkflowNameFromFile -FilePath $FilePath
            $Type = 'PowerShellWorkflow'
        }
        else
        {
            $Name = Get-ScriptNameFromFileName -FilePath $FilePath
            $Type = 'PowerShell'
        }

        if(Test-AzureAutomationRunbookExist -Name $Name `
                                            -Credential $Credential `
                                            -AutomationAccountName $AutomationAccountName `
                                            -SubscriptionName $SubscriptionName `
                                            -ResourceGroupName $ResourceGroupName `
                                            -Tenant $Tenant)
        {
            $Runbook = Get-AzureRmAutomationRunbook -Name $Name `
                                                    -ResourceGroupName $ResourceGroupName `
                                                    -AutomationAccountName $AutomationAccountName
            $Tags = $Runbook.Tags
            if($Tags.ContainsKey('CurrentCommit')) { $RunbookCurrentCommit = $Tags.CurrentCommit }
            else { $RunbookCurrentCommit = -1 }
            if($RunbookCurrentCommit -ne $CurrentCommit) { $Tags.CurrentCommit = $CurrentCommit ; $Update = $True }
            else { $Update = $False }
            
            $Description = $Runbook.Description
            $CurrentRunbookType = $Runbook.RunbookType

            # Currently the API calls PowerShellWorkflow Script ...
            if($CurrentRunbookType -eq 'Script') { $CurrentRunbookType = 'PowerShellWorkflow' }
        }
        else
        {
            $Tags = @{ 
                'RepositoryName' = $RepositoryName
                'CurrentCommit' = $CurrentCommit
            }
            
            $Update = $True
            $Description = Select-FirstValid $Runbook.Description,"$([string]::Empty)"
            $CurrentRunbookType = $Type
        }
    }
    Catch
    {
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch ($Exception.FullyQualifiedErrorId)
        {
            Default
            {
                Throw
            }
        }
    }

    Write-CompletedMessage @CompletedParams
    Return @{ 
        'Update' = $Update
        'CurrentRunbookType' = $CurrentRunbookType
        'ParameterSet' = @{
            'Name' = $Name
            'Type' = $Type
            'Tags' = $Tags
            'AutomationAccountName' = $AutomationAccountName
            'ResourceGroupName' = $ResourceGroupName
            'Path' = $FilePath
            'Description' = $Description
            'Force' = $True
            'Published' = $True
        }
    }
}
Function Get-AzureAutomationGlobalInformation
{
    Param(
        [Parameter(Mandatory = $True)]
        [String] 
        $Name,

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
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [String]
        $CurrentCommit = '-1',

        [Parameter(Mandatory = $True)]
        [String]
        [ValidateSet('Variable','Schedule')]
        $Type,

        [Parameter(Mandatory = $False)]
        [String]
        $Tenant = $null
    )

    $CompletedParams = Write-StartingMessage -String $Name
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $tenant
        
        if(Test-AzureAutomationGlobalExist -Name $Name `
                                           -Credential $Credential `
                                           -AutomationAccountName $AutomationAccountName `
                                           -SubscriptionName $SubscriptionName `
                                           -ResourceGroupName $ResourceGroupName `
                                           -Type $Type `
                                           -Tenant $tenant)
        {
            Switch($Type)
            {
                'Variable'
                {
                    $Global = Get-AzureRmAutomationVariable -Name $Name `
                                                            -AutomationAccountName $AutomationAccountName `
                                                            -ResourceGroupName $ResourceGroupName
                    $Command = 'Set-AzureRmAutomationVariable'
                }
                'Schedule'
                {
                    $Global = Get-AzureRmAutomationSchedule -Name $Name `
                                                            -AutomationAccountName $AutomationAccountName `
                                                            -ResourceGroupName $ResourceGroupName
                    $Command = 'UpdateSchedule'
                }
            }
            $TagUpdate = New-ChangesetTagLine -TagLine $Global.Description`
                                              -CurrentCommit $CurrentCommit `
                                              -RepositoryName $RepositoryName
            $Description = "$($TagUpdate.TagLine)"
            $Update = $TagUpdate.NewVersion
        }
        else
        {
            Switch($Type)
            {
                'Variable'
                {
                    $Description = "$($Variable.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                    $Command = 'New-AzureRmAutomationVariable'
                    $Update = $True
                }
                'Schedule'
                {
                    $Description = "$($Variable.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                    $Command = 'NewSchedule'
                    $Update = $True
                }
            }
        }
    }
    Catch
    {
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch ($Exception.FullyQualifiedErrorId)
        {
            Default
            {
                Throw
            }
        }
    }
    
    Write-CompletedMessage @CompletedParams
    Return @{
        'Update' = $Update
        'Command' = $Command
        'ParameterSet' = @{
            'Name' = $Name
            'Description' = $Description
            'AutomationAccountName' = $AutomationAccountName
            'ResourceGroupName' = $ResourceGroupName
        }
    }
}
Function Connect-AzureRmAccount
{
    Param(
        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,
        
        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName,

        [Parameter(Mandatory = $False)]
        [String]
        $Tenant
    )

    $CompletedParams = Write-StartingMessage -String $SubscriptionName
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        $SPNParams = @{
            'ServicePrincipal' = $True
            'Tenant' = $Tenant
        }
        if(-not (Get-Module -Name AzureRM.profile)) { $Null = Import-Module -Name AzureRM.profile *>&1 }
        if(-not (Test-AzureRMConnection -Credential $Credential -SubscriptionName $SubscriptionName))
        {
            Write-Verbose -Message 'Establishing new connection'
            if($Tenant -as [bool])
            {
                $Null = Add-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName @SPNParams
            }
            else
            {
                $Null = Add-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName
            }
        }
        else
        {
            Write-Verbose -Message 'Using current connection'
        }
    }
    Catch
    {
        Throw
    }
    Write-CompletedMessage @CompletedParams
}
Function Test-AzureRMConnection
{
    Param(
        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,
        
        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName
    )
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParams = Write-StartingMessage
    Try
    {
        $AzureContext = Get-AzureRmContext
        if(
            ($AzureContext.Account.Id -eq $Credential.UserName) -and
            ($AzureContext.Subscription.SubscriptionName-eq $SubscriptionName)
           )
        {
            $Connected = $True
        }
        else
        {
            $Connected = $False
        }
    }
    Catch
    {
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception

        Switch($ExceptionInfo.FullyQualifiedErrorId)
        {
            'InvalidOperation,Microsoft.Azure.Commands.Profile.GetAzureRMContextCommand'
            {
                $Connected = $False
            }
            Default
            {
                Throw
            }
        }
    }
    Write-CompletedMessage @CompletedParams -Status "[Connected [$Connected]]"
    Return $Connected
}

<#
#>
Function Set-AzureAutomationIntegrationTag
{
    Param(
        [Parameter(
            Mandatory = $True,
            ValueFromPipeLine = $True,
            Position = 0
        )]
        [ValidateSet(
            'Runbook',
            'Variable',
            'Schedule'
        )]
        [string]
        $Type,

        [Parameter(
            Mandatory = $True,
            ValueFromPipeLine = $True,
            Position = 1
        )]
        [string]
        $Name,

        [Parameter(
            Mandatory = $True,
            ValueFromPipeLine = $True,
            Position = 2
        )]
        [string]
        [ValidateSet('CurrentCommit','RepositoryName')]
        $TagName,

        [Parameter(
            Mandatory = $True,
            ValueFromPipeLine = $True,
            Position = 3
        )]
        [string]
        $Value,

        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,
        
        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [String]
        $AutomationAccountName,

        [Parameter(Mandatory = $True)]
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [String]
        $Tenant = $Null
    )
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParams = Write-StartingMessage

    Try
    {
        Connect-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName -Tenant $Tenant

        $CommonParameters = @{
            'ResourceGroupName' = $ResourceGroupName
            'AutomationAccountName' = $AutomationAccountName
        }

        Switch($Type)
        {
            'Runbook'
            {
                $Runbook = Get-AzureRmAutomationRunbook -Name $Name @CommonParameters
                $Tags = $Runbook.Tags
                if($Tags.ContainsKey($TagName))
                {
                    $Tags.$TagName = $Value
                }
                else
                {
                    $Null = $Tags += @{ $TagName = $Value }
                }
                $Null = Set-AzureRmAutomationRunbook -Name $Name -Tags $Tags @CommonParameters
            }
            'Variable'
            {
                $Variable = Get-AzureRmAutomationVariable -Name $Name @CommonParameters
                $DescriptionObj = ConvertFrom-AutomationDescriptionTagLine -InputObject $Variable.Description
                $DescriptionObj.$TagName = $Value
                $UpdatedDescription = ConvertTo-AutomationDescriptionTagLine @DescriptionObj
                $Null = Set-AzureRmAutomationVariable -Name $Name -Description $UpdatedDescription @CommonParameters
            }
            'Schedule'
            {
                $Schedule = Get-AzureRmAutomationSchedule -Name $Name @CommonParameters
                $DescriptionObj = ConvertFrom-AutomationDescriptionTagLine -InputObject $Schedule.Description
                $DescriptionObj.$TagName = $Value
                $UpdatedDescription = ConvertTo-AutomationDescriptionTagLine @DescriptionObj
                $Null = Set-AzureRmAutomationSchedule -Name $Name -Description $UpdatedDescription @CommonParameters
            }
        }
    }
    Catch
    {
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch($ExceptionInfo.FullyQualifiedErrorId)
        {
            Default
            {
                Throw
            }
        }
    }
    
    Write-CompletedMessage @CompletedParams
}

Function ConvertFrom-AutomationDescriptionTagLine
{
    Param(
        [Parameter(
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [string]
        $InputObject
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParams = Write-StartingMessage -Stream Debug

    $KeyValueHT = @{
        'Description' = $InputObject
        'CurrentCommit' = 'Unknown'
        'RepositoryName' = 'Unknown'
    }
    if($InputObject -match $RepositoryNameRegex)
    {
        $KeyValueHT.RepositoryName = $Matches[1]
    }

    if($InputObject -match $CurrentCommitRegex)
    {
        $KeyValueHT.CurrentCommit = $Matches[1]
    }
    
    Write-CompletedMessage @CompletedParams -Status ($KeyValueHT | ConvertTo-Json)
    Return $KeyValueHT
}

Function ConvertTo-AutomationDescriptionTagLine
{
    Param(
        [Parameter(
            Mandatory = $True,
            ValueFromPipeline = $True,
            Position = 0
        )]
        [string]
        $Description,

        [Parameter(
            Mandatory = $True,
            ValueFromPipeline = $True,
            Position = 1
        )]
        [string]
        $CurrentCommit,

        [Parameter(
            Mandatory = $True,
            ValueFromPipeline = $True,
            Position = 2
        )]
        [string]
        $RepositoryName
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParams = Write-StartingMessage -Stream Debug

    $Description = $Description -replace $RepositoryNameRegex, "__RepositoryName:$($RepositoryName);"
    $Description = $Description -replace $CurrentCommitRegex, "CurrentCommit:$($CurrentCommit);__"
    
    Write-CompletedMessage @CompletedParams -Status $Description
    Return $Description
}
Export-ModuleMember -Function * -Verbose:$false