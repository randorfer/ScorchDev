workflow Test-VerboseWorkflow
{
    $VerbosePreference = 'SilentlyContinue'
    foreach($i in 0..200)
    {
        Write-Verbose -Message 'Test String'
    }
}

workflow Test-InlineScriptInnerWorkflow
{
    $VerbosePreference = 'SilentlyContinue'
    foreach($i in 0..200)
    {
        InlineScript
        {
            Write-Verbose -Message 'Test String'
        }
    }
}

workflow Test-InlineScriptOuterWorkflow
{
    $VerbosePreference = 'SilentlyContinue'
    InlineScript
    {
        foreach($i in 0..200)
        {
            Write-Verbose -Message 'Test String'
        }
    }
}

Measure-Command -Expression { Test-VerboseWorkflow }
Measure-Command -Expression { Test-InlineScriptInnerWorkflow }
Measure-Command -Expression { Test-InlineScriptOuterWorkflow }
# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUHmAuMn3ibilN6qObD0yAEVzE
# 4XmgggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQU/odktMomk+K0GClefD8/iBcGNlwwDQYJKoZIhvcNAQEBBQAEgYDJ7VqlISnI
# 8DU4iTjLzC1OYX3Sd2mg6b9LWl5weBBhhXUFbMaap8wDITpy5RreVrdIXYruaUWr
# WhZ59AaUyk5s7qYC1NmkDSN2PYvXIahpZa6Okhy1pjFZVYM2Y3TRTDIUaQK//3IW
# TKjbaUOUE994cMtuL/m5Ff+F8o0yHCjkQQ==
# SIG # End signature block
