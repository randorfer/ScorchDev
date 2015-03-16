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
        $IPAddress = (nslookup.exe $Target $Server `
            | Select-String -AllMatches `
                            -Pattern '(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}' `
            | Select-Object -ExpandProperty Matches `
            | Select-Object -ExpandProperty Value)[1]
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
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUFQhZpYpcTYtR6KlUVrFy6WYK
# n8CgggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUGV0Ksujmap6kGJGg7KBup/54fsAwDQYJKoZIhvcNAQEBBQAEgYCMFMm4ga2F
# XJXIAmzhbonloHN+4rNC9gXkx5Jq//VqDVit3JizUvY7mrn6g0idNYP/UDVn9UhX
# Xx/E16H6/9uEmpcqtead3h7v+vsHWVEjnq3RCdGXxvX0SWm0W4QqWl0GnleAPUqD
# A7cUNtRDEEioYE435pmuYUrvE/OZV+OHNw==
# SIG # End signature block
