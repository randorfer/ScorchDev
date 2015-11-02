<#
    .Synopsis
#>
workflow Deploy-Integration
{
    Param($currentcommit,$repositoryname)
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Foreach($RunbookFile in (Get-ChildItem -Path ..\Runbooks -Recurse -Filter *.ps1))
    {
        Publish-SMARunbookChange -FilePath $RunbookFile.FullName -CurrentCommit $currentcommit -RepositoryName $repositoryname
    }
    Foreach($SettingsFile in (Get-ChildItem -Path ..\Globals -Recurse -Filter *.json))
    {
        Publish-SMASettingsFileChange -FilePath $SettingsFile.FullName -CurrentCommit $currentcommit -RepositoryName $repositoryname
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}
# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUrxVXnF41FFxVkXo1LQlTavWV
# U96gggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUs/R9i9WJrMVqVAxUIifv/uH8WwswDQYJKoZIhvcNAQEBBQAEgYCLOln8LbNW
# Pm3v5FPCqO3t23EOCPN/P4YYqfwXUpzAjx0nTMoaEKVqzzQh2RWG/GiFbH+lNdiK
# 7sziMT5QuGb3I9t9G/Lc3T0Jih2xbhxUAdznuYuMPPTvziIq1Zt4F1tbb6jEGYle
# ZpVT/PdWkKr28EIEiX8j92Z+tqXRHMe82Q==
# SIG # End signature block
