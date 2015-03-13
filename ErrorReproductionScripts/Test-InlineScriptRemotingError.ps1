<#
    Here’s an example of a simpler workflow that demonstrates the bug:
    It generates an error after the third iteration. But because of the ErrorActionPreference, the $i variable isn’t updated appropriately and you get 10 iterations.

    Fixed in PSv5
#>

workflow Test-InlineScriptRemotingError
{
    foreach ($i in 1..10)
    {
        inlinescript
        {
            $errorActionPreference = "Stop"
 
            "Before: " + $using:i
            if($using:i -gt 3)
            {
                Write-Error -Message Error
            }
            "After."
        } -PSComputerName localhost
    }
}

workflow Test-InlineScriptRemotingErrorWorkaround
{
    foreach ($i in 1..10)
    {
        inlinescript
        {
            & {
                $errorActionPreference = "Stop"
 
                "Before: " + $using:i
                if($using:i -gt 3)
                {
                    Write-Error -Message Error
                }
                "After."
            }
        } -PSComputerName localhost
    }
}
# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU/mUh+C0DeAvC6mPYYdumDHn6
# RNOgggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUdCB1pBFhGfzVe/ERuxMkLKqNxikwDQYJKoZIhvcNAQEBBQAEgYCJYhpRS3Q/
# HSZiOaEf8nbPqewaShEcP02VN3T2d4sCytsnPhOP8u6JMq6SZfyEdD4KvNtr0vOU
# me3sN0vVK2HgBwA4wrpLOWg77EbvTASL5CzGeNOx/8O0k3KX7krX/JPP4vJ7Q+8/
# C5KNyUHOhg/sP0f7AaIX3jorkC9JTOTXfw==
# SIG # End signature block
