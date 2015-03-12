$DumpPath = "D:\ProcDump\$(Get-Date -Format 'MM-dd-yyyy-hh-mm-ss')"
$ProcDumpExeFolder = 'D:\ProcDump'
$ProcDumpExePath = "$ProcDumpExeFolder\ProcDump.exe"
$ProcDumpDownloadURI = 'http://live.sysinternals.com/tools/procdump.exe'
$ProcessList = @('Orchestrator.Sandbox')
$LogmanDataCollectorSetName = 'LowMemoryDetection'

Invoke-Expression "Logman.exe Stop $LogmanDataCollectorSetName"
if(-not (Test-Path -Path $ProcDumpExePath))
{
    New-Item -ItemType Directory -Path $ProcDumpExeFolder -Force
    Invoke-WebRequest -Uri $ProcDumpDownloadURI -OutFile $ProcDumpExePath
    Unblock-File -Path $ProcDumpExePath
}
                    
if(-not (Test-Path -Path $DumpPath))
{
    Write-Verbose -Message "Dump path did not exist for this computer - creating [$DumpPath]"
    New-Item -ItemType Directory -Path $DumpPath
}

foreach($ProcessName in $ProcessList)
{
    $ProcessIds = (Get-Process -Name $ProcessName).Id
    foreach($ProcessId in $ProcessIds)
    {
        $ProcDumpCommand = "$($ProcDumpExePath) -ma $ProcessId $($DumpPath) -accepteula"
        Write-Verbose -Message "Starting Procdump [$ProcDumpCommand]"
        Invoke-Expression -Command $ProcDumpCommand
    }
}
# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUj7XdgfInWCXs9/lWe/EWKH5N
# C/KgggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUs83O3eVmdw2KoZr/d6Khsj0clpIwDQYJKoZIhvcNAQEBBQAEgYBithzGiwK+
# PeHD1iFqanAgDm8GkngzzDxjq+NIIWZdzcJHEizGsMIpAjmDedsF39xqitH7uXA/
# QqkT86hRJT/xgeKb6HQ5ZdCrjmuq5qemdo+C0JjdIOMCsFrkWwXUvzel5vU/2Fwp
# MKzQJluAbRK/+6gZaGP0WPlAPGp0Fh+8aQ==
# SIG # End signature block
