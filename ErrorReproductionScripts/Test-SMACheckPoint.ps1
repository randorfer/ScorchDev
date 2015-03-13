<#
    Breaks in SMA -- Maximum stream length exceeded (5000000 bytes)

    This appears to be a limitation imposed within this file. “:\Program Files\Microsoft System Center 2012 R2\Service Management Automation\Orchestrator.Sandbox.exe.config"
 
    Which imposes the limit on the sandbox and I believe this is more to do with ASP.NET(?) than writing to the DB but not sure.
    Bumping this setting up in the file will allow it to complete but I can’t comment on whether this is safe and what max limit should be. The below setting bumped mine up to ~95 MB and that seemed to work without issue in SMA. 
 
    <?xml version="1.0"?>
    <configuration>
      <system.diagnostics configSource="Orchestrator.Sandbox.Diagnostics.config" />
      <startup useLegacyV2RuntimeActivationPolicy="true">
        <supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.0"/>
      </startup>
      <appSettings>
        <add key="MaxStreamLength" value="100000000" />
      </appSettings>
    </configuration>
    
    ID	   Title	                                                            Assigned To	State	    Work Item Type
    389248 Maximum stream size that a runbook worker is configured with is low	Beth Cooper	Resolved	Bug
#>

Workflow Test-SMACheckPoint
{
    Write-Verbose -Message "Starting to create file"
    inlinescript 
    {
        if(Test-Path -Path "C:\temp\sizeTest.txt") { Remove-Item -Path "C:\temp\sizeTest.txt" -Force }
        for($i = 0; $i -lt 5000000/360; $i++)
        {
            $content = '............................................................' +
                       '............................................................' + 
                       '............................................................' +
                       '............................................................' +
                       '............................................................' +
                       '............................................................'
            Add-Content -Value $content -Path c:\temp\sizeTest.txt -Force
        }
    }
    Write-Verbose -Message "File Created - Checkpointing"
    Checkpoint-Workflow
    Write-Verbose -Message "Reading File"
    $var = Get-Content -Path "C:\temp\sizeTest.txt"
    Write-Verbose -Message "Checkpointing"
    Checkpoint-Workflow
    Write-Verbose -Message "Post Checkpoint Removing File"
    if(Test-Path -Path "C:\temp\sizeTest.txt") { inlinescript { Remove-Item -Path "C:\temp\sizeTest.txt" -Force } }
    Write-Verbose -Message "File Removed"
}

# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUkMh0hFQ3hw7UBtVSQ/jwn2VT
# rEGgggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUwgrxQnb6olB+VAzXUZE8P2+oVg4wDQYJKoZIhvcNAQEBBQAEgYBLBapxTB1A
# LNwNwVrm4clUxIuDRISF8XnNTsqXTFvqnzrSE/6P8kMiubkCq3cJaE/2H4xjI4I2
# ua6JNHcxsS2hpyLY+Nouv4Fpo+vxxLr9gCqmsY9/nwvP0EGZUjHFqqYJEhe8AmAY
# DifEI/G+Dwd2jq63S+xMO549g73IFkZFuA==
# SIG # End signature block
