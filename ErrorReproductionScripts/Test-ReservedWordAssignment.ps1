<#
Produces this:

The workflow 'Test-ReservedWordAssignment' could not be started: The following errors were encountered while processing the workflow tree:
'DynamicActivity': The private implementation of activity '1: DynamicActivity' has the following validation error:   Compiler error(s) encountered processing expression "To".
Expression expected.
At line:383 char:21
+                     throw (New-Object System.Management.Automation.ErrorRecord $ ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidArgument: (System.Manageme...etersDictionary:PSBoundParametersDictionary) [], RuntimeException
    + FullyQualifiedErrorId : StartWorkflow.InvalidArgument
#>
workflow Test-ReservedWordAssignment
{
    $To = 'somebody@somewhere.net'
}

# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUaNHB5dxPd6V6us/6wPWZC80b
# 9rOgggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUioXoXxdjBvgTt/2IEc0UyPy/oKwwDQYJKoZIhvcNAQEBBQAEgYAmQfADRB29
# Ts7KK7G/tQnaRO3leq9A9rCFNN6lR5yFPWezIlk7M1foD3Pot/NKG8X083UrNS28
# ywyJ9QJ1kP0lPCZfKMA8rjn1UWDgPrNfDTki1uGtSGeUqb2amngAbVvWes6+qTvv
# n5Gzn1uGHomq9XKUKXh7SdIp5xr+7MaN4Q==
# SIG # End signature block
