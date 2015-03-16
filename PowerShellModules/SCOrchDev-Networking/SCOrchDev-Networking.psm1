<# 
.Synopsis
    Uses NSLookup to convert a Target's IP Address

.Parameter Target
    The Target machine to lookup

.Parameter Server
    The name of the nameserver to target the lookup to

.Example
    PS C:\Users\G521601> Get-ComputerIPAddress -Host mgoapsmad1
    146.217.167.149

.Example
    PS C:\Users\G521601> Get-ComputerIPAddress -Host mgoapsmad1 -Server mgodc1
    146.217.167.149
#>
function Get-IPAddressFromDNS
{
    Param(
        [Parameter(Mandatory=$True,
        ValueFromPipeline=$True)]
        [String]
        $Target,

        [Parameter(Mandatory=$False)]
        [String]
        $Server
    )

    $Null = $(
        $NSLookupResult = nslookup.exe $Target $Server 2>$null
        $IPAddress = ($NSLookupResult  | Select-String -AllMatches `
                                                         -Pattern '(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}' `
            | Select-Object -ExpandProperty Matches `
            | Select-Object -ExpandProperty Value)
        if($IPAddress.Count -ne 2)
        {
            Throw-Exception -Type 'RecordNotFound' `
                            -Message 'DNS Record not found for target' `
                            -Property @{ 'Target' = $Target ; 
                                         'Server' = $Server ;
                                         'NSLookupResult' = $NSLookupResult }
        }
        else
        {
            $IPAddress = $IPAddress[1]
        }
    )
    Return $IPAddress
}
<# 
.Synopsis
    Uses NSLookup to find a targets name

.Parameter Target
    The Target machine to lookup

.Parameter Server
    The name of the nameserver to target the lookup to

.Example
    PS C:\Users\G521601> Get-ComputerIPAddress -Host mgoapsmad1
    146.217.167.149

.Example
    PS C:\Users\G521601> Get-ComputerIPAddress -Host mgoapsmad1 -Server mgodc1
    146.217.167.149
#>
function Get-NameFromDNS
{
    Param(
        [Parameter(Mandatory=$True,
        ValueFromPipeline=$True)]
        [String]
        $Target,

        [Parameter(Mandatory=$False)]
        [String]
        $Server
    )

    $Null = $(
        $NSlookupResult = nslookup.exe $Target $Server
        if("$($NSlookupResult)" -match 'Name:\s+([\w\.]+)')
        {
            $ComputerName = $Matches[1]
        }
        else
        {
            Throw-Exception -Type 'ComputerNameNotFoundInDNS' `
                            -Message 'Could not find Computer name in DNS' `
                            -Property @{ 'NSLookupResult' = $NSlookupResult ;
                                         'Target' = $Target ;
                                         'Server' = $Server }
        }
    )
    Return $ComputerName
}
Export-ModuleMember -Function * -Verbose:$false
# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUpJHUVCHhhRxnWHSBYTKOJh0n
# zC6gggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUFeGs8EFux5oo7gplldhBHh+HuFQwDQYJKoZIhvcNAQEBBQAEgYCQPeUZ7wWw
# O/d2n6v23etEaY28LlQ6LMcnIxUs4akX3U5ZBtRhx7FEDMw2+3q73kk/zA2Svz5e
# 8GzYln1k6eggpthhmrgtrAJ7uw263nZZeW7p2dym3rrHb5b6Jk+F4NO9fhG4grBd
# J36wARliNmfyOVZrqye83O+6WevnjrdSig==
# SIG # End signature block
