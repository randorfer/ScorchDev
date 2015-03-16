<#
    .Synopsis
        Takes a json file and publishes all schedules and variables from it into SMA
    
    .Parameter FilePath
        The path to the settings file to process

    .Parameter CurrentCommit
        The current commit to tag the variables and schedules with

    .Parameter RepositoryName
        The Repository Name that will 'own' the variables and schedules
#>
Workflow Publish-SMASettingsFileChange
{
    Param( [Parameter(Mandatory=$True)][String] $FilePath,
           [Parameter(Mandatory=$True)][String] $CurrentCommit,
           [Parameter(Mandatory=$True)][String] $RepositoryName)
    
    Write-Verbose -Message "[$FilePath] Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

    Try
    {
        $Variables = ConvertFrom-PSCustomObject (ConvertFrom-JSON (Get-SmaGlobalFromFile -FilePath $FilePath -GlobalType Variables))
        foreach($VariableName in $Variables.Keys)
        {
            Write-Verbose -Message "[$VariableName] Updating"
            $Variable = $Variables."$VariableName"
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
            $SmaVariable = Get-SmaVariable -Name $VariableName `
                                           -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                           -Port $CIVariables.WebservicePort `
                                           -Credential $SMACred
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
            if(Test-IsNullOrEmpty $SmaVariable.VariableId.Guid)
            {
                Write-Verbose -Message "[$($VariableName)] is a New Variable"
                $VariableDescription = "$($Variable.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                $NewVersion = $True
            }
            else
            {
                Write-Verbose -Message "[$($VariableName)] is an existing Variable"
                $TagUpdate = ConvertFrom-JSON( New-SmaChangesetTagLine -TagLine $SmaVariable.Description`
                                                         -CurrentCommit $CurrentCommit `
                                                         -RepositoryName $RepositoryName )
                $VariableDescription = "$($TagUpdate.TagLine)"
                $NewVersion = $TagUpdate.NewVersion
            }
            if($NewVersion)
            {
                if(ConvertTo-Boolean $Variable.isEncrypted)
                {
                    $CreateEncryptedVariable = Set-SmaVariable -Name $VariableName `
													           -Value $Variable.Value `
														       -Description $VariableDescription `
                                                               -Encrypted `
														       -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                               -Port $CIVariables.WebservicePort `
                                                               -Credential $SMACred `
                                                               -Force
                }
                else
                {
                    $CreateNonEncryptedVariable = Set-SmaVariable -Name $VariableName `
													              -Value $Variable.Value `
														          -Description $VariableDescription `
														          -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                                  -Port $CIVariables.WebservicePort `
                                                                  -Credential $SMACred
                }
            }
            else
            {
                Write-Verbose -Message "[$($VariableName)] Is not a new version. Skipping"
            }
            Write-Verbose -Message "[$($VariableName)] Finished Updating"
        }

        $Schedules = ConvertFrom-PSCustomObject (ConvertFrom-JSON (Get-SmaGlobalFromFile -FilePath $FilePath -GlobalType Schedules))
        foreach($ScheduleName in $Schedules.Keys)
        {
            Write-Verbose -Message "[$ScheduleName] Updating"
            try
            {
                $Schedule = $Schedules."$ScheduleName"
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                $SmaSchedule = Get-SmaSchedule -Name $ScheduleName `
                                               -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                               -Port $CIVariables.WebservicePort `
                                               -Credential $SMACred
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                if(Test-IsNullOrEmpty $SmaSchedule.ScheduleId.Guid)
                {
                    Write-Verbose -Message "[$($ScheduleName)] is a New Schedule"
                    $ScheduleDescription = "$($Schedule.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                    $NewVersion = $True
                }
                else
                {
                    Write-Verbose -Message "[$($ScheduleName)] is an existing Schedule"
                    $TagUpdate = ConvertFrom-JSON( New-SmaChangesetTagLine -TagLine $SmaVariable.Description`
                                                             -CurrentCommit $CurrentCommit `
                                                             -RepositoryName $RepositoryName )
                    $ScheduleDescription = "$($TagUpdate.TagLine)"
                    $NewVersion = $TagUpdate.NewVersion
                }
                if($NewVersion)
                {
                    $CreateSchedule = Set-SmaSchedule -Name $ScheduleName `
                                                      -Description $ScheduleDescription `
                                                      -ScheduleType DailySchedule `
                                                      -DayInterval $Schedule.DayInterval `
                                                      -StartTime $Schedule.NextRun `
                                                      -ExpiryTime $Schedule.ExpirationTime `
                                                      -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                      -Port $CIVariables.WebservicePort `
                                                      -Credential $SMACred

                    if(Test-IsNullOrEmpty $CreateSchedule)
                    {
                        Throw-Exception -Type 'ScheduleFailedToCreate' `
                                        -Message 'Failed to create the schedule' `
                                        -Property @{ 'ScheduleName' = $ScheduleName ;
                                                     'Description' = $ScheduleDescription;
                                                     'ScheduleType' = 'DailySchedule' ;
                                                     'DayInterval' = $Schedule.DayInterval ;
                                                     'StartTime' = $Schedule.NextRun ;
                                                     'ExpiryTime' = $Schedule.ExpirationTime ;
                                                     'WebServiceEndpoint' = $CIVariables.WebserviceEndpoint ;
                                                     'Port' = $CIVariables.WebservicePort ;
                                                     'Credential' = $SMACred.UserName }
                    }
                    try
                    {
                        $Parameters   = ConvertFrom-PSCustomObject -InputObject $Schedule.Parameter `
                                                                   -MemberType NoteProperty `

                        $RunbookStart = Start-SmaRunbook -Name $schedule.RunbookName `
                                                         -ScheduleName $ScheduleName `
                                                         -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                         -Port $CIVariables.WebservicePort `
                                                         -Parameters $Parameters `
                                                         -Credential $SMACred
                        if(Test-IsNullOrEmpty $RunbookStart)
                        {
                            Throw-Exception -Type 'ScheduleFailedToSet' `
                                            -Message 'Failed to set the schedule on the target runbook' `
                                            -Property @{ 'ScheduleName' = $ScheduleName ;
                                                         'RunbookName' = $Schedule.RunbookName ; 
                                                         'Parameters' = $(ConvertTo-Json $Parameters) }
                        }
                    }
                    catch
                    {
                        Remove-SmaSchedule -Name $ScheduleName `
                                           -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                           -Port $CIVariables.WebservicePort `
                                           -Credential $SMACred `
                                           -Force
                        Write-Exception $_ -Stream Warning
                    }
                                                  
                }
            }
            catch
            {
                Write-Exception $_ -Stream Warning
            }
            Write-Verbose -Message "[$($ScheduleName)] Finished Updating"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "[$FilePath] Finished [$WorkflowCommandName]"
}

# SIG # Begin signature block
# MIIOfQYJKoZIhvcNAQcCoIIObjCCDmoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUelPrI/ElRjQ+6v2NboRcgLny
# 5cqgggqQMIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# CisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBSJVnTO
# lC+FiDh/LLqy8T6HsLU23DANBgkqhkiG9w0BAQEFAASBgLuNCC6WT0R5FBNMbvbE
# ZRCNRCYMnlz3s8lPjvIxbMLVIJJwfaDu9tQBlXPWHlcd0sbl7iDcRb4nYhquJoUY
# gRyCSN6uJnfp0lHZbv6r5bU2YaOkypOuKrZ4V4eq+4COYGA8FYZbcvyEy/0ap12Z
# GCzi3uCjxw1kuLKr6s5W3XBZoYICCzCCAgcGCSqGSIb3DQEJBjGCAfgwggH0AgEB
# MHIwXjELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9u
# MTAwLgYDVQQDEydTeW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0g
# RzICEA7P9DjI/r81bgTYapgbGlAwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJAzEL
# BgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1MDMxNjIwMTczM1owIwYJKoZI
# hvcNAQkEMRYEFMnhGfILMN8qxInVvrivE4Ci9RTKMA0GCSqGSIb3DQEBAQUABIIB
# AAP7o/m++HuO/QWLe9RrF8UfjMo7IahRElplLJ7E5f7RT5bC0lbtFh7tuwtWuID2
# lM53/8fDbv4mNRWwgiiBqXfZPhvzROCG1gZ7aU+eCiCigMPknJNPkEM/i9ZUvteU
# NtP+1ylGIJII0NbmdrMzHR0+ksAPRBHdyEDOu22L66tRoxNfXIOk8BPP8J8L9vhn
# wuiHjJvOo2Ryrhytq4VuB/7ZDTnucmVowhOTkZZ4YZyoEhglQlBo3Zjqr02O5WkX
# HCgSR/8G5FM9uQ6tV9rf8Av6++Zj9TSlPMbgy/2XR63TdOib9bfBGr8Zue/Xkpub
# hEzwTN2c9l5gvpc9X4+IVOY=
# SIG # End signature block
