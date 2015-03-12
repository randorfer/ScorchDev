$DumpPath = "C:\ProcDump\$(Get-Date -Format 'mm-dd-yyyy-hh-mm-ss')"
$ProcDumpExePath = 'c:\ProcDump\ProcDump.exe'
$ProcDumpDownloadURI = 'http://live.sysinternals.com/tools/procdump.exe'
$ProcessList = @('Orchestrator.Sandbox')
if(-not (Test-Path -Path $ProcDumpExePath))
{
    Write-Warning -Message (New-Exception -Type 'ProcDumpExeNotFound' `
                                          -Message 'Could not find the procdump.exe executable. Attempting download' `
                                          -Property @{
                                                        'ProcDumpExePath'   = $ProcDumpExePath
                                                        'ComputerName'      = $Env:ComputerName
                                                        'ProcDumpDownloadURI' = $ProcDumpDownloadURI
                            })
                   
    New-FileItemContainer -FileItemPath $RemoteProcDumpVars.ProcDumpExePath
    Invoke-WebRequest -Uri $RemoteProcDumpVars.ProcDumpDownloadURI -OutFile $RemoteProcDumpVars.ProcDumpExePath
    Unblock-File -Path $RemoteProcDumpVars.ProcDumpExePath
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
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU/JbbyTqXZaRc9TBzQME/afcn
# g7+gggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUDJBw1q1iTiu3yiijg4nt9ZpA7WIwDQYJKoZIhvcNAQEBBQAEgYDVKQQLC3Ui
# k4y5qrnkbiw+xlQrgKDcnijC+AgW442rRg6ZFt4gSACf+Zh7SehNr8VzRf7m9Sk6
# xqsDrBCUn/wM45wa1L+j1Q4ym7gWGNHKZz58O2joXQxofBuu6FhBsrAhJ88L3ThY
# KwWURiMLozUlvJyTPrUVkZxaTfDpnOlDYg==
# SIG # End signature block
