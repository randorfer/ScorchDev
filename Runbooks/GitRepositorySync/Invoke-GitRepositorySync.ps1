<#
.Synopsis
    Check GIT repository for new commits. If found sync the changes into
    the current SMA environment

.Parameter RepositoryName
#>
Workflow Invoke-GitRepositorySync
{
    Param(
        [Parameter(Mandatory = $true)]
        [String]
        $RepositoryName
    )
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('RepositoryInformation',
                                                       'SubscriptionAccessCredentialName',
                                                       'SubscriptionName',
                                                       'AutomationAccountName',
                                                       'RunbookWorkerAccessCredenialName') `
                                               -Prefix 'ContinuousIntegration'
    $SubscriptionAccessCredential = Get-AutomationPSCredential -Name $CIVariables.SubscriptionAccessCredentialName
    $RunbookWorkerAccessCredenial = Get-AutomationPSCredential -Name $CIVariables.RunbookWorkerAccessCredenialName
    Try
    {
        $RepositoryInformation = (ConvertFrom-Json -InputObject $CIVariables.RepositoryInformation)."$RepositoryName"
        Write-Verbose -Message "`$RepositoryInformation [$(ConvertTo-Json -InputObject $RepositoryInformation)]"

        $RunbookWorker = Get-AzureAutomationHybridRunbookWorker -Name $RepositoryInformation.HybridWorkerGroup
        
        # Update the repository on all SMA Workers
        InlineScript
        {
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Continue
            & {
                $null = $(
                    $DebugPreference       = [System.Management.Automation.ActionPreference]::SilentlyContinue
                    $VerbosePreference     = [System.Management.Automation.ActionPreference]::SilentlyContinue
                    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                    
                    $RepositoryInformation = $Using:RepositoryInformation
                    Update-GitRepository -RepositoryInformation $RepositoryInformation
                )
            }
        } -PSComputerName $RunbookWorker -PSCredential $RunbookWorkerAccessCredenial

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
                                                          -AutomationAccountName $CIVariables.AutomationAccountName `
                                                          -SubscriptionName $CIVariables.SubscriptionName
                Checkpoint-Workflow
            }
            # Not yet implemented
            <#
            Foreach($ModulePath in $ReturnInformation.ModuleFiles)
            {
                Try
                {
                    $PowerShellModuleInformation = Test-ModuleManifest -Path $ModulePath
                    $PowerShellModuleInformation = Publish-AzureAutomationPowerShellModule -ModulePath $ModulePath `
                                                                                           -SubscriptionName $CIVariables.SubscriptionName `
                                                                                           -AutomationAccountName $CIVariables.AutomationAccountName `
                                                                                           -Credential $SubscriptionAccessCredential `
                                                                                           -CurrentCommit $RepositoryChange.CurrentCommit `
                                                                                           -RepositoryName $RepositoryName
                }
                Catch
                {
                    $Exception = New-Exception -Type 'ImportSmaPowerShellModuleFailure' `
                                               -Message 'Failed to import a PowerShell module into Sma' `
                                               -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString $_) ;
                        'ModulePath' = $ModulePath ;
                        'ModuleName' = $ModuleName ;
                        'ModuleVersion' = $ModuleVersion ;
                        'PowerShellModuleInformation' = "$(ConvertTo-JSON $PowerShellModuleInformation)" ;
                        'WebserviceEnpoint' = $CIVariables.WebserviceEndpoint ;
                        'Port' = $CIVariables.WebservicePort ;
                        'Credential' = $SMACred.UserName ;
                    }
                    Write-Warning -Message $Exception -WarningAction Continue
                }
                Checkpoint-Workflow
            }
            #>
            Foreach($RunbookFilePath in $ReturnInformation.ScriptFiles)
            {
                Publish-AzureAutomationRunbookChange -FilePath $RunbookFilePath `
                                                     -CurrentCommit $RepositoryChange.CurrentCommit `
                                                     -RepositoryName $RepositoryName `
                                                     -Credential $SubscriptionAccessCredential `
                                                     -AutomationAccountName $CIVariables.AutomationAccountName `
                                                     -SubscriptionName $CIVariables.SubscriptionName
                Checkpoint-Workflow
            }
            
            if($ReturnInformation.CleanRunbooks)
            {
                Remove-AzureAutomationOrphanRunbook -RepositoryName $RepositoryName `
                                                    -SubscriptionName $CIVariables.SubscriptionName `
                                                    -AutomationAccountName $CIVariables.AutomationAccountName `
                                                    -Credential $SubscriptionAccessCredential `
                                                    -RepositoryInformation $RepositoryInformation
                Checkpoint-Workflow
            }
            if($ReturnInformation.CleanAssets)
            {
                Remove-AzureAutomationOrphanAsset -RepositoryName $RepositoryName `
                                                  -SubscriptionName $CIVariables.SubscriptionName `
                                                  -AutomationAccountName $CIVariables.AutomationAccountName `
                                                  -Credential $SubscriptionAccessCredential `
                                                  -RepositoryInformation $RepositoryInformation
                Checkpoint-Workflow
            }
            <# Not yet implemented
            if($ReturnInformation.CleanModules)
            {
                #Remove-SmaOrphanModule
                Checkpoint-Workflow
            }
            #>
            if($ReturnInformation.ModuleFiles)
            {
                Try
                {
                    Write-Verbose -Message 'Validating Module Path on Runbook Wokers'
                    $RepositoryModulePath = "$($RepositoryInformation.Path)\$($RepositoryInformation.PowerShellModuleFolder)"
                    inlinescript
                    {
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
                    } -PSComputerName $RunbookWorker -PSCredential $RunbookWorkerAccessCredenial
                    Write-Verbose -Message 'Finished Validating Module Path on Runbook Wokers'
                }
                Catch
                {
                    Write-Exception -Exception $_ -Stream Warning
                }
                
                Checkpoint-Workflow
            }
            $UpdatedRepositoryInformation = (Set-RepositoryInformationCommitVersion -RepositoryInformation $CIVariables.RepositoryInformation `
                                                                                    -RepositoryName $RepositoryName `
                                                                                    -Commit $RepositoryChange.CurrentCommit) -as [string]
            $VariableUpdate = Set-AutomationVariable -Name 'ContinuousIntegration-RepositoryInformation' `
                                                     -Value $UpdatedRepositoryInformation

            Write-Verbose -Message "Finished Processing [$($RepositoryInformation.CurrentCommit)..$($RepositoryChange.CurrentCommit)]"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}
