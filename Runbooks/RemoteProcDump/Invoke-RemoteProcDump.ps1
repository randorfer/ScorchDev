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
# MIIOfQYJKoZIhvcNAQcCoIIObjCCDmoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUfnBqGwcUOUlHnwEQ17EAdG98
# R5egggqQMIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
# AQUFADAUMRIwEAYDVQQDDAlTQ09yY2hEZXYwHhcNMTUwMzA5MTQxOTIxWhcNMTkw
# MzA5MDAwMDAwWjAUMRIwEAYDVQQDDAlTQ09yY2hEZXYwgZ8wDQYJKoZIhvcNAQEB
# BQADgY0AMIGJAoGBANbZ1OGvnyPKFcCw7nDfRgAxgMXt4YPxpX/3rNVR9++v9rAi
# pY8Btj4pW9uavnDgHdBckD6HBmFCLA90TefpKYWarmlwHHMZsNKiCqiNvazhBm6T
# XyB9oyPVXLDSdid4Bcp9Z6fZIjqyHpDV2vas11hMdURzyMJZj+ibqBWc3dAZAgMB
# AAGjRjBEMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBQ75WLz6WgzJ8GD
# ty2pMj8+MRAFTTAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQEFBQADgYEAoK7K
# SmNLQ++VkzdvS8Vp5JcpUi0GsfEX2AGWZ/NTxnMpyYmwEkzxAveH1jVHgk7zqglS
# OfwX2eiu0gvxz3mz9Vh55XuVJbODMfxYXuwjMjBV89jL0vE/YgbRAcU05HaWQu2z
# nkvaq1yD5SJIRBooP7KkC/zCfCWRTnXKWVTw7hwwggPuMIIDV6ADAgECAhB+k+v7
# fMZOWepLmnfUBvw7MA0GCSqGSIb3DQEBBQUAMIGLMQswCQYDVQQGEwJaQTEVMBMG
# A1UECBMMV2VzdGVybiBDYXBlMRQwEgYDVQQHEwtEdXJiYW52aWxsZTEPMA0GA1UE
# ChMGVGhhd3RlMR0wGwYDVQQLExRUaGF3dGUgQ2VydGlmaWNhdGlvbjEfMB0GA1UE
# AxMWVGhhd3RlIFRpbWVzdGFtcGluZyBDQTAeFw0xMjEyMjEwMDAwMDBaFw0yMDEy
# MzAyMzU5NTlaMF4xCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jw
# b3JhdGlvbjEwMC4GA1UEAxMnU3ltYW50ZWMgVGltZSBTdGFtcGluZyBTZXJ2aWNl
# cyBDQSAtIEcyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsayzSVRL
# lxwSCtgleZEiVypv3LgmxENza8K/LlBa+xTCdo5DASVDtKHiRfTot3vDdMwi17SU
# AAL3Te2/tLdEJGvNX0U70UTOQxJzF4KLabQry5kerHIbJk1xH7Ex3ftRYQJTpqr1
# SSwFeEWlL4nO55nn/oziVz89xpLcSvh7M+R5CvvwdYhBnP/FA1GZqtdsn5Nph2Up
# g4XCYBTEyMk7FNrAgfAfDXTekiKryvf7dHwn5vdKG3+nw54trorqpuaqJxZ9YfeY
# cRG84lChS+Vd+uUOpyyfqmUg09iW6Mh8pU5IRP8Z4kQHkgvXaISAXWp4ZEXNYEZ+
# VMETfMV58cnBcQIDAQABo4H6MIH3MB0GA1UdDgQWBBRfmvVuXMzMdJrU3X3vP9vs
# TIAu3TAyBggrBgEFBQcBAQQmMCQwIgYIKwYBBQUHMAGGFmh0dHA6Ly9vY3NwLnRo
# YXd0ZS5jb20wEgYDVR0TAQH/BAgwBgEB/wIBADA/BgNVHR8EODA2MDSgMqAwhi5o
# dHRwOi8vY3JsLnRoYXd0ZS5jb20vVGhhd3RlVGltZXN0YW1waW5nQ0EuY3JsMBMG
# A1UdJQQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIBBjAoBgNVHREEITAfpB0w
# GzEZMBcGA1UEAxMQVGltZVN0YW1wLTIwNDgtMTANBgkqhkiG9w0BAQUFAAOBgQAD
# CZuPee9/WTCq72i1+uMJHbtPggZdN1+mUp8WjeockglEbvVt61h8MOj5aY0jcwsS
# b0eprjkR+Cqxm7Aaw47rWZYArc4MTbLQMaYIXCp6/OJ6HVdMqGUY6XlAYiWWbsfH
# N2qDIQiOQerd2Vc/HXdJhyoWBl6mOGoiEqNRGYN+tjCCBKMwggOLoAMCAQICEA7P
# 9DjI/r81bgTYapgbGlAwDQYJKoZIhvcNAQEFBQAwXjELMAkGA1UEBhMCVVMxHTAb
# BgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMTAwLgYDVQQDEydTeW1hbnRlYyBU
# aW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0gRzIwHhcNMTIxMDE4MDAwMDAwWhcN
# MjAxMjI5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50ZWMg
# Q29ycG9yYXRpb24xNDAyBgNVBAMTK1N5bWFudGVjIFRpbWUgU3RhbXBpbmcgU2Vy
# dmljZXMgU2lnbmVyIC0gRzQwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCiYws5RLi7I6dESbsO/6HwYQpTk7CY260sD0rFbv+GPFNVDxXOBD8r/amWltm+
# YXkLW8lMhnbl4ENLIpXuwitDwZ/YaLSOQE/uhTi5EcUj8mRY8BUyb05Xoa6IpALX
# Kh7NS+HdY9UXiTJbsF6ZWqidKFAOF+6W22E7RVEdzxJWC5JH/Kuu9mY9R6xwcueS
# 51/NELnEg2SUGb0lgOHo0iKl0LoCeqF3k1tlw+4XdLxBhircCEyMkoyRLZ53RB9o
# 1qh0d9sOWzKLVoszvdljyEmdOsXF6jML0vGjG/SLvtmzV4s73gSneiKyJK4ux3DF
# vk6DJgj7C72pT5kI4RAocqrNAgMBAAGjggFXMIIBUzAMBgNVHRMBAf8EAjAAMBYG
# A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDBzBggrBgEFBQcB
# AQRnMGUwKgYIKwYBBQUHMAGGHmh0dHA6Ly90cy1vY3NwLndzLnN5bWFudGVjLmNv
# bTA3BggrBgEFBQcwAoYraHR0cDovL3RzLWFpYS53cy5zeW1hbnRlYy5jb20vdHNz
# LWNhLWcyLmNlcjA8BgNVHR8ENTAzMDGgL6AthitodHRwOi8vdHMtY3JsLndzLnN5
# bWFudGVjLmNvbS90c3MtY2EtZzIuY3JsMCgGA1UdEQQhMB+kHTAbMRkwFwYDVQQD
# ExBUaW1lU3RhbXAtMjA0OC0yMB0GA1UdDgQWBBRGxmmjDkoUHtVM2lJjFz9eNrwN
# 5jAfBgNVHSMEGDAWgBRfmvVuXMzMdJrU3X3vP9vsTIAu3TANBgkqhkiG9w0BAQUF
# AAOCAQEAeDu0kSoATPCPYjA3eKOEJwdvGLLeJdyg1JQDqoZOJZ+aQAMc3c7jecsh
# aAbatjK0bb/0LCZjM+RJZG0N5sNnDvcFpDVsfIkWxumy37Lp3SDGcQ/NlXTctlze
# vTcfQ3jmeLXNKAQgo6rxS8SIKZEOgNER/N1cdm5PXg5FRkFuDbDqOJqxOtoJcRD8
# HHm0gHusafT9nLYMFivxf1sJPZtb4hbKE4FtAC44DagpjyzhsvRaqQGvFZwsL0kb
# 2yK7w/54lFHDhrGCiF3wPbRRoXkzKy57udwgCRNx62oZW8/opTBXLIlJP7nPf8m/
# PiJoY1OavWl0rMUdPH+S4MO8HNgEdTGCA1cwggNTAgEBMCgwFDESMBAGA1UEAwwJ
# U0NPcmNoRGV2AhAR1XrqJ493rkLXCYnbxd0ZMAkGBSsOAwIaBQCgeDAYBgorBgEE
# AYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwG
# CisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBT3hInu
# h/0s1ky4hj0nn8XTsW7m/TANBgkqhkiG9w0BAQEFAASBgKxskRymFQXEfeNa6vW5
# a+35Ow1D65asHfi5B34kDouCWejAFIRJsPGdbtSKvVwKkxqAv/IlLF0yqt5bguqY
# 3NjIohGS+qkouWZE9EqfgJrUTvicOADlfcU7UHXtQip0oWlpnrf60zwMrla0AlWW
# /csJ4+9yX4suKJM67alQY+TsoYICCzCCAgcGCSqGSIb3DQEJBjGCAfgwggH0AgEB
# MHIwXjELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9u
# MTAwLgYDVQQDEydTeW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0g
# RzICEA7P9DjI/r81bgTYapgbGlAwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJAzEL
# BgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1MDMxNzIyMDkyMVowIwYJKoZI
# hvcNAQkEMRYEFALj1iD2MBbF4X2tilF0vHs5xqh9MA0GCSqGSIb3DQEBAQUABIIB
# ACiUcsxB2I+5/kFtWanwF6FCmyQKj5L3suWY51paefDesRYcjocoWRTHSQZ8rZBo
# gxpTWr030ctNt85gO7Nw+9uTV7D9yhlM2VmnExs+RfYFTxCBku89V1lckjY1TTAQ
# 7PEazxYgnz48Ah5+60MgB818s5YYvy/7h47uM2/xf0a3G1mXfAvp6Cfsp8Vrs4j7
# oYt67cSZ8UtQ9hlDf75e7xJvPryhi7gQI64L2DR46rG4naYpi9irkZPMG66wy6iS
# wioZkuaKImc/pMKFwsccGjJPWeIeDpGJniBKKuWQ7IbmTHA0LNHNEKBM5508Zl6K
# DrDjviIxckaBy13lc14ysu8=
# SIG # End signature block
