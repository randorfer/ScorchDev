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
                                                       'SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName
    Try
    {
        $RepositoryInformation = (ConvertFrom-Json -InputObject $CIVariables.RepositoryInformation)."$RepositoryName"
        Write-Verbose -Message "`$RepositoryInformation [$(ConvertTo-Json -InputObject $RepositoryInformation)]"

        $RunbookWorker = Get-SMARunbookWorker
        
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
        } -PSComputerName $RunbookWorker -PSCredential $SMACred

        $RepositoryChangeJSON = Find-GitRepositoryChange -RepositoryInformation $RepositoryInformation
        $RepositoryChange = ConvertFrom-Json -InputObject $RepositoryChangeJSON
        if("$($RepositoryChange.CurrentCommit)" -ne "$($RepositoryInformation.CurrentCommit)")
        {
            Write-Verbose -Message "Processing [$($RepositoryInformation.CurrentCommit)..$($RepositoryChange.CurrentCommit)]"
            Write-Verbose -Message "RepositoryChange [$RepositoryChangeJSON]"
            $ReturnInformationJSON = Group-RepositoryFile -Files $RepositoryChange.Files `
                                                          -RepositoryInformation $RepositoryInformation
            $ReturnInformation = ConvertFrom-Json -InputObject $ReturnInformationJSON
            Write-Verbose -Message "ReturnInformation [$ReturnInformationJSON]"
            Foreach($RunbookFilePath in $ReturnInformation.ScriptFiles)
            {
                Publish-SMARunbookChange -FilePath $RunbookFilePath `
                                         -CurrentCommit $RepositoryChange.CurrentCommit `
                                         -RepositoryName $RepositoryName
                Checkpoint-Workflow
            }
            Foreach($SettingsFilePath in $ReturnInformation.SettingsFiles)
            {
                Publish-SMASettingsFileChange -FilePath $SettingsFilePath `
                                         -CurrentCommit $RepositoryChange.CurrentCommit `
                                         -RepositoryName $RepositoryName
                Checkpoint-Workflow
            }
            foreach($ModulePath in $ReturnInformation.ModuleFiles)
            {
                Try
                {
                    $PowerShellModuleInformation = Test-ModuleManifest -Path $ModulePath
                    $ModuleName = $PowerShellModuleInformation.Name -as [string]
                    $ModuleVersion = $PowerShellModuleInformation.Version -as [string]
                    $PowerShellModuleInformation = Import-SmaPowerShellModule -ModulePath $ModulePath `
                                                                              -WebserviceEndpoint $CIVariables.WebserviceEndpoint `
                                                                              -WebservicePort $CIVariables.WebservicePort `
                                                                              -Credential $SMACred
                    SetAutomationModuleActivityMetadata -ModuleName $ModuleName `
                                                        -ModuleVersion $ModuleVersion
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
                    Write-Exception -Exception $Exception -Stream Warning
                }
                
                Checkpoint-Workflow
            }
            
            if($ReturnInformation.CleanRunbooks)
            {
                Remove-SmaOrphanRunbook -RepositoryName $RepositoryName
                Checkpoint-Workflow
            }
            if($ReturnInformation.CleanAssets)
            {
                Remove-SmaOrphanAsset -RepositoryName $RepositoryName
                Checkpoint-Workflow
            }
            if($ReturnInformation.CleanModules)
            {
                Remove-SmaOrphanModule
                Checkpoint-Workflow
            }
            if($ReturnInformation.ModuleFiles)
            {
                Try
                {
                    Write-Verbose -Message 'Validating Module Path on Runbook Wokers'
                    $RepositoryModulePath = "$($RepositoryInformation.Path)\$($RepositoryInformation.PowerShellModuleFolder)"
                    inlinescript
                    {
                        Add-PSEnvironmentPathLocation -Path $Using:RepositoryModulePath
                    } -PSComputerName $RunbookWorker -PSCredential $SMACred
                    Write-Verbose -Message 'Finished Validating Module Path on Runbook Wokers'
                }
                Catch
                {
                    $Exception = New-Exception -Type 'PowerShellModulePathValidationError' `
                                               -Message 'Failed to set PSModulePath' `
                                               -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString $_) ;
                        'RepositoryModulePath' = $RepositoryModulePath ;
                        'RunbookWorker' = $RunbookWorker ;
                    }
                    Write-Exception -Exception $Exception -Stream Warning
                }
                
                Checkpoint-Workflow
            }
            $UpdatedRepositoryInformation = (Set-SmaRepositoryInformationCommitVersion -RepositoryInformation $CIVariables.RepositoryInformation `
                                                                                       -RepositoryName $RepositoryName `
                                                                                       -Commit $RepositoryChange.CurrentCommit) -as [string]
            $VariableUpdate = Set-SmaVariable -Name 'SMAContinuousIntegration-RepositoryInformation' `
                                              -Value $UpdatedRepositoryInformation `
                                              -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                              -Port $CIVariables.WebservicePort `
                                              -Credential $SMACred

            Write-Verbose -Message "Finished Processing [$($RepositoryInformation.CurrentCommit)..$($RepositoryChange.CurrentCommit)]"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}

# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU6JM64s8E2vomcAtezNDjJPzx
# bDGgggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
# AQUFADAUMRIwEAYDVQQDDAlTQ09yY2hEZXYwHhcNMTUwMzA5MTQxOTIxWhcNMTkw
# MzA5MDAwMDAwWjAUMRIwEAYDVQQDDAlTQ09yY2hEZXYwgZ8wDQYJKoZIhvcNAQEB
# BQADgY0AMIGJAoGBANbZ1OGvnyPKFcCw7nDfRgAxgMXt4YPxpX/3rNVR9++v9rAi
# pY8Btj4pW9uavnDgHdBckD6HBmFCLA90TefpKYWarmlwHHMZsNKiCqiNvazhBm6T
# XyB9oyPVXLDSdid4Bcp9Z6fZIjqyHpDV2vas11hMdURzyMJZj+ibqBWc3dAZAgMB
# AAGjRjBEMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBQ75WLz6WgzJ8GD
# ty2pMj8+MRAFTTAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQEFBQADgYEAoK7K
# SmNLQ++VkzdvS8Vp5JcpUi0GsfEX2AGWZ/NTxnMpyYmwEkzxAveH1jVHgk7zqglS
# OfwX2eiu0gvxz3mz9Vh55XuVJbODMfxYXuwjMjBV89jL0vE/YgbRAcU05HaWQu2z
# nkvaq1yD5SJIRBooP7KkC/zCfCWRTnXKWVTw7hwxggFIMIIBRAIBATAoMBQxEjAQ
# BgNVBAMMCVNDT3JjaERldgIQEdV66iePd65C1wmJ28XdGTAJBgUrDgMCGgUAoHgw
# GAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGC
# NwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQx
# FgQUo5iuo4p0hgX2EMi/nwU/TCmT7bQwDQYJKoZIhvcNAQEBBQAEgYC0UmobFb28
# bQseJBP9B6JLVt+M4tvm64Z1D8M6be27gYQiQ6AiJUf9tiuEAPjHtyC2foC3RSnr
# 9vM5FhL5zlFT81sApWi+CowFMsybyGeTujiBLB8/BT9MOKdKtjJCfztjQAC0SUB7
# BHCfI0j0Erg4l1xro86pz/qMU6p5m2W13w==
# SIG # End signature block
