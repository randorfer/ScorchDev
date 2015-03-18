<#
    .Synopsis
        Checks a SMA environment and removes any modules that are not found
        in the local psmodulepath
#>
Workflow Remove-SmaOrphanModule
{
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Try
    {
        $CIVariables = Get-BatchAutomationVariable -Name @('SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
        $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

        $SmaModule = Get-SmaModule -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                   -Port $CIVariables.WebservicePort `
                                   -Credential $SMACred

        $LocalModule = Get-Module -ListAvailable -Refresh -Verbose:$false

        if(-not ($SmaModule -and $LocalModule))
        {
            if(-not $SmaModule)   { Write-Warning -Message 'No modules found in SMA. Not cleaning orphan modules' }
            if(-not $LocalModule) { Write-Warning -Message 'No modules found in local PSModule Path. Not cleaning orphan modules' }
        }
        else
        {
            $ModuleDifference = Compare-Object -ReferenceObject  $SmaModule.ModuleName `
                                               -DifferenceObject $LocalModule.Name
            Foreach($Difference in $ModuleDifference)
            {
                if($Difference.SideIndicator -eq '<=')
                {
                    Try
                    {
                        Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                        <#
                        TODO: Investigate / Test before uncommenting. Potential to brick an environment

                        Remove-SmaModule -Name $Difference.InputObject `
                                         -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                         -Port $CIVariables.WebservicePort `
                                         -Credential $SMACred
                        #>
                        Write-Verbose -Message "[$($Difference.InputObject)] Removed from SMA"
                    }
                    Catch
                    {
                        $Exception = New-Exception -Type 'RemoveSmaModuleFailure' `
                                                   -Message 'Failed to remove a Sma Module' `
                                                   -Property @{
                            'ErrorMessage' = (Convert-ExceptionToString $_) ;
                            'RunbookName' = $Difference.InputObject ;
                            'WebserviceEnpoint' = $CIVariables.WebserviceEndpoint ;
                            'Port' = $CIVariables.WebservicePort ;
                            'Credential' = $SMACred.UserName ;
                        }
                        Write-Warning -Message $Exception -WarningAction Continue
                    }
                }
            }
        }
    }
    Catch
    {
        $Exception = New-Exception -Type 'RemoveSmaOrphanModuleWorkflowFailure' `
                                   -Message 'Unexpected error encountered in the Remove-SmaOrphanModule workflow' `
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
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUehq494pyJHbCShc9qgBc0cY1
# mk+gggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQU9vnmMEdTSAjeRsd70CRnjhOLW0kwDQYJKoZIhvcNAQEBBQAEgYC7beYgYJ8q
# QcuVDvBRLnhyRUtzChQZUS2lr6n5BmE/HdtEW3Kif2hfrapNLtlq75etSmD8OXyz
# FQsGYaqW0G6TgGIF6knbXwW4FYIf1jCQ4UZL4f8SVC+8+xtCiknnZsrIa0x3IsSw
# EPsmSLXvq4zrsOtGUkUGHpEUedtqiMn+hQ==
# SIG # End signature block
