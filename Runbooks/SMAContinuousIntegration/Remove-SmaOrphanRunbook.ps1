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
    Try
    {
        $CIVariables = Get-BatchAutomationVariable -Name @('RepositoryInformation',
                                                           'SMACredName',
                                                           'WebserviceEndpoint'
                                                           'WebservicePort') `
                                                   -Prefix 'SMAContinuousIntegration'
        $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

        $RepositoryInformation = (ConvertFrom-JSON -InputObject $CIVariables.RepositoryInformation)."$RepositoryName"

        $SmaRunbooks = Get-SMARunbookPaged -WebserviceEndpoint $CIVariables.WebserviceEndpoint `
                                           -Port $CIVariables.WebservicePort `
                                           -Credential $SMACred
        if($SmaRunbooks) { $SmaRunbookTable = Group-SmaRunbooksByRepository -InputObject $SmaRunbooks }
        $RepositoryWorkflows = Get-GitRepositoryWorkflowName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.RunbookFolder)"
        $Differences = Compare-Object -ReferenceObject $SmaRunbookTable.$RepositoryName.RunbookName `
                                      -DifferenceObject $RepositoryWorkflows
    
        Foreach($Difference in $Differences)
        {
            if($Difference.SideIndicator -eq '<=')
            {
                Try
                {
                    Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                    Remove-SmaRunbook -Name $Difference.InputObject `
                                      -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                      -Port $CIVariables.WebservicePort `
                                      -Credential $SMACred
                    Write-Verbose -Message "[$($Difference.InputObject)] Removed from SMA"
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveSmaRunbookFailure' `
                                               -Message 'Failed to remove a Sma Runbook' `
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
    Catch
    {
        $Exception = New-Exception -Type 'RemoveSmaOrphanRunbookWorkflowFailure' `
                                   -Message 'Unexpected error encountered in the Remove-SmaOrphanRunbook workflow' `
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
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUuQQ5xY/+L2hyocjb3HOwAEKk
# zL2gggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUreCiBGwXjJ8wGquDaCj8WJy6UkgwDQYJKoZIhvcNAQEBBQAEgYBNfRo0q1qh
# BTJrApI8/unYIVR1lHxwWy30NyWSWuLnyYP5qpx7wedVqVB4XQ30lYum3itpnpKO
# KuUk670lDMLFIcLk2ENiTr4vVPXzBKAQeHG+dSn3bWRkacdYB+JOlxbstvsV75GY
# 7jHxckISBzhZYxcT+i4Vuc7aJduBXRwqDw==
# SIG # End signature block
