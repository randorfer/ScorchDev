<#
    .Synopsis
        Monitors Sma Runbook workers. When they are found to be unhealthy
        invokes a process dump for the top processes running
#>

Workflow Monitor-SmaRunbookWorker
{
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $SmaRunbookWorkerVars = Get-BatchAutomationVariable -Name @('WebServiceEndpoint', 
                                                                'WebServicePort', 
                                                                'AccessCredName', 
                                                                'MinimumPercentFreeMemory', 
                                                                'MinimumProcDumpPerDay', 
                                                                'DaysToKeepProcDump', 
                                                                'ProcDumpPath', 
                                                                'ProcessesToDumpJSON') `
                                                        -Prefix 'SmaRunbookWorker'
    $AccessCred = Get-AutomationPSCredential -Name $SmaRunbookWorkerVars.AccessCredName
    $Worker = Get-SMARunbookWorker

    Do
    {
        Foreach -Parallel ($Worker in (Get-SMARunbookWorker))
        {
            $DumpPath = "$($SmaRunbookWorkerVars.ProcDumpPath)\$(Get-Date -Format MM-d-yyyy)\$($env:COMPUTERNAME)"
            $WorkerStatus = Test-SmaRunbookWorker -RunbookWorker $Worker `
                                                  -AccessCred $AccessCred
        
            if($WorkerStatus -eq 'Healthy')
            {
                
            }
            else
            {
                Invoke-RemoteProcDump -ComputerName $Worker `
                                      -DumpPath $DumpPath `
                                      -ProcessList $SmaRunbookWorkerVars.ProcessesToDumpJSON `
                                      -AccessCredName $SmaRunbookWorkerVars.AccessCredName
            }

            # Cleanup old process dumps
            # Implement Delay Cycle
        }
    }
    While($MonitorActive)

    Start-SmaRunbook -Name $WorkflowCommandName
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}

# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUjChza7CkpM+LyVXTrAm6RLsZ
# 7rWgggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUjuRY2fEizsKKBP0pYbXomfec+hswDQYJKoZIhvcNAQEBBQAEgYAfB+BuarKW
# D3hf7+9JghTihst0/s78K5YioOcTfhAanDx1WNCLvNYRvWFkqxMmDg1F+XUQVeq1
# Q8OSiN3PH5CP5cVqHW/kd9zy5C/ht98IpnYeBS6k2T+IoOzIyLGkJ21PUpy+H393
# Sdjus1KOud1h5F0ZtYGcRZhLOJStnRdlDw==
# SIG # End signature block
