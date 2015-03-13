<#
    Serialization / Deserialization is very slow for complex objects
#>

workflow Test-CredentialFromPSToWorkflow
{
    Write-Verbose -Message 'Before InlineScript'
    $Cred = InlineScript
    {
        $SecurePassword = ConvertTo-SecureString -String 'MyTestPassword' -AsPlainText -Force
        $Cred = New-Object -TypeName 'System.Management.Automation.PSCredential' -ArgumentList 'TestUser', $SecurePassword
        Write-Verbose -Message 'Got the credential in the InlineScript'
        # The InlineScript will never return
        return $Cred
    }
    Write-Verbose -Message 'After InlineScript'
}
# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUO4kYPUboQcuGM74fqlQHUm9Y
# mzOgggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUfSAVJaxYIaUrvTr1SJ1EWawSx20wDQYJKoZIhvcNAQEBBQAEgYAi1CA7bXEQ
# HUDsBBvDZVJnkLDPCFxkuhhFDxPQZ718mwGB8fjAICZrD30u4Pa3HR9de0jaf3zd
# i7YRz2bmA/eCuoTWetTWOm/RjXL9rpljv0z3ZUgDalv50sAQoXnNvtzDgghBdT+b
# T0m899I6ANAD9uciXkIuyHOBn7feLOjHOg==
# SIG # End signature block
