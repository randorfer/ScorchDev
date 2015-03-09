<#
.Synopsis
    Starts Procdump on a target machine.
    
.Description
    Invokes proc dump on a target machine and creates dumps to a target location. Will create
    dumps of all instances of the passed process names.

    Uses PSAuthentication CredSSP to be able to write the dumps out to a network share.
    Expectes procdump to be at the location specified in the RemoteProcDump-ProcDumpExePath
    location. If it is not found there it will attempt to download online from the url specified
    in RemoteProcDump-ProcDumpDownloadURI.

.Parameter ComputerName
    The remote computer to run procdump on.

.Parameter ProcessList
    A JSON array of processes to capture a procdump for.
    
.Parameter DumpPath
    A string representing the location to save the procdump to.

.Parameter AccessCredName
    A String representing the name of a powershell credential stored in the SMA environment.
    This string will be used to retrieve the corresponding credential which will be used to
    invoke the remoting to the computer passed in the ComputerName property. If not passed
    the default user name specified in RemoteProcDump-AccessCredName will be used.

.Parameter AuthenticationMechanism
    The Authentication mechanism for PS Remoting. Default is Default.

.Example
    Workflow Test-InvokeRemoteProcDump
    {
        $RunbookWorker = Get-SMARunbookWorker
        $ProcessList = @('Orchestrator.Sandbox','W3WP') | ConvertTo-JSON -Compress
        Foreach -Parallel ($ComputerName in $RunbookWorker)
        {
            Invoke-RemoteProcDump -ComputerName $ComputerName `
            -ProcessList $ProcessList
        }
    }
    Test-InvokeRemoteProcDump
#>
Workflow Invoke-RemoteProcDump
{
    Param([Parameter(Mandatory = $True) ]
          [String]
          $ComputerName,
          
          [Parameter(Mandatory = $True) ]
          [String] 
          $DumpPath,
          
          [Parameter(Mandatory = $True)]
          [String]
          $ProcessList,
          
          [Parameter(Mandatory = $False)]
          [String]
          $AccessCredName,
          
          [Parameter(Mandatory = $False)]
          [ValidateSet('Basic','CredSSP','Default','Digest','Kerberos','Negotiate','NegotiateWithImplicitCredential')]
          $AuthenticationMechanism = 'Default')

    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    
    $RemoteProcDumpVars = Get-BatchAutomationVariable -Name @('AccessCredName', 
                                                              'ProcDumpExePath', 
                                                              'ProcDumpDownloadURI') `
                                                      -Prefix 'RemoteProcDump'
    
    $AccessCred = Get-AutomationPSCredential -Name (Select-FirstValid -Value @($AccessCredName, 
                                                                               $RemoteProcDumpVars.AccessCredName))
    inlinescript
    {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Continue
        & {
            $null = $(
                $DebugPreference       = [System.Management.Automation.ActionPreference]$Using:DebugPreference
                $VerbosePreference     = [System.Management.Automation.ActionPreference]$Using:VerbosePreference
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

                $RemoteProcDumpVars = $Using:RemoteProcDumpVars
                $DumpPath           = $Using:DumpPath
                $ProcessList        = $Using:ProcessList

                if(-not (Test-Path -Path $RemoteProcDumpVars.ProcDumpExePath))
                {
                    Write-Warning -Message (New-Exception -Type 'ProcDumpExeNotFound' `
                                                          -Message 'Could not find the procdump.exe executable. Attempting download' `
                                                          -Property @{
                                                                       'ProcDumpExePath'   = $RemoteProcDumpVars.ProcDumpExePath
                                                                       'ComputerName'      = $Env:ComputerName
                                                                       'ProcDumpDownloadURI' = $RemoteProcDumpVars.ProcDumpDownloadURI
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

                $ProcessNames = ConvertFrom-Json -InputObject $ProcessList
                foreach($ProcessName in $ProcessNames)
                {
                    $ProcessIds = (Get-Process -Name $ProcessName).Id
                    foreach($ProcessId in $ProcessIds)
                    {
                        $ProcDumpCommand = "$($ProcDumpVars.ProcDumpExePath) -ma $ProcessId $($DumpPath) -accepteula"
                        Write-Verbose -Message "Starting Procdump [$ProcDumpCommand]"
                        Invoke-Expression -Command $ProcDumpCommand
                    }
                }
            )
        }
    } -PSComputerName $ComputerName -PSCredential $AccessCred -PSAuthentication $AuthenticationMechanism

    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}
# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUfnBqGwcUOUlHnwEQ17EAdG98
# R5egggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQU94SJ7of9LNZMuIY9J5/F07Fu5v0wDQYJKoZIhvcNAQEBBQAEgYCsbJEcphUF
# xH3jWur1uWvt+TsNQ+uWrB34uQd+JA6LglnowBSESbDxnW7Uir1cCpMagL/yJSxd
# MqreW4LqmNzYyKIRkvqpKLlmRPRKn4Ca1E74nDgA5X3FO1B17UIqdKFpaZ63+tM8
# DK5WtAJVlv3LCePvcl+LLiiTOu2pUGPk7A==
# SIG # End signature block
