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
    Try
    {
        $CIVariables = Get-BatchAutomationVariable -Name @('RepositoryInformation', 
                                                       'SMACredName', 
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                                   -Prefix 'SMAContinuousIntegration'
        $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

        $RepositoryInformation = (ConvertFrom-Json -InputObject $CIVariables.RepositoryInformation)."$RepositoryName"

        $SmaVariables = Get-SmaVariable -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                        -Port $CIVariables.WebservicePort `
                                        -Credential $SMACred
        if($SmaVariables) 
        {
            $SmaVariableTable = Group-SmaAssetsByRepository -InputObject $SmaVariables 
        }

        $SmaSchedules = Get-SmaSchedule -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                        -Port $CIVariables.WebservicePort `
                                        -Credential $SMACred
        if($SmaSchedules) 
        {
            $SmaScheduleTable = Group-SmaAssetsByRepository -InputObject $SmaSchedules 
        }

        $RepositoryAssets = Get-GitRepositoryAssetName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.RunbookFolder)"

        if($SmaVariableTable."$RepositoryName")
        {
            $VariableDifferences = Compare-Object -ReferenceObject $SmaVariableTable."$RepositoryName".Name `
                                                  -DifferenceObject $RepositoryAssets.Variable
            Foreach($Difference in $VariableDifferences)
            {
                Try
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
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveSmaAssetFailure' `
                                                -Message 'Failed to remove a Sma Asset' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString $_) ;
                        'AssetName' = $Difference.InputObject ;
                        'AssetType' = 'Variable' ;
                        'WebserviceEnpoint' = $CIVariables.WebserviceEndpoint ;
                        'Port' = $CIVariables.WebservicePort ;
                        'Credential' = $SMACred.UserName ;
                    }
                    Write-Exception -Exception $Exception -Stream Warning
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
                Try
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
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveSmaAssetFailure' `
                                                -Message 'Failed to remove a Sma Asset' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString $_) ;
                        'AssetName' = $Difference.InputObject ;
                        'AssetType' = 'Schedule' ;
                        'WebserviceEnpoint' = $CIVariables.WebserviceEndpoint ;
                        'Port' = $CIVariables.WebservicePort ;
                        'Credential' = $SMACred.UserName ;
                    }
                    Write-Exception -Exception $Exception -Stream Warning
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
        $Exception = New-Exception -Type 'RemoveSmaOrphanAssetWorkflowFailure' `
                                   -Message 'Unexpected error encountered in the Remove-SmaOrphanAsset workflow' `
                                   -Property @{
            'ErrorMessage' = (Convert-ExceptionToString $_) ;
            'RepositoryName' = $RepositoryName ;
        }
        Write-Exception -Exception $Exception -Stream Warning
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}

# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUqv20xHKNI4Nx/n3q/Jnnzpmo
# vUCgggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQU3OD9APY+r3nGaPdbrT4nj58LXYEwDQYJKoZIhvcNAQEBBQAEgYCDP5Qpw7Fk
# PO6o+GdpbWmCqwbZ7GJhzX3lNzMubpyFNYCxwvY7Qx+MS/U+CC8CAlYrdIeSQBmT
# u64352vjVOqcpANlH2RbCG68OAiAo5SSNWwqDJEOWDv8j/fJgQtW8srF/G4r10Os
# x8sTaXuLb1vMv/z38nTq5Xbnr1mUDWN1iQ==
# SIG # End signature block
