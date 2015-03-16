<#
    .Synopsis
        Check GIT repository for new commits. If found sync the changes into
        the current SMA environment

    .Parameter RepositoryName
#>
Workflow Invoke-GitRepositorySync
{
    Param([Parameter(Mandatory=$true)][String] $RepositoryName)
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('RepositoryInformation',
                                                       'SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName
    Try
    {
        $RepositoryInformation = (ConvertFrom-Json $CIVariables.RepositoryInformation)."$RepositoryName"
        Write-Verbose -Message "`$RepositoryInformation [$(ConvertTo-JSON $RepositoryInformation)]"

        $RunbookWorker = Get-SMARunbookWorker
        
        # Update the repository on all SMA Workers
        InlineScript
        {
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Continue
		    & {
			    $null = $(
				    $DebugPreference       = [System.Management.Automation.ActionPreference]::SilentlyContinue
				    $VerbosePreference     = [System.Management.Automation.ActionPreference]::SilentlyContinue
				    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                    
                    $RepositoryInformation = $Using:RepositoryInformation
                    Update-GitRepository -RepositoryInformation $RepositoryInformation
                )
            }
        } -PSComputerName $RunbookWorker -PSCredential $SMACred

        $RepositoryChangeJSON = Find-GitRepositoryChange -RepositoryInformation $RepositoryInformation
        $RepositoryChange = ConvertFrom-JSON $RepositoryChangeJSON
        if("$($RepositoryChange.CurrentCommit)" -ne "$($RepositoryInformation.CurrentCommit)")
        {
            Write-Verbose -Message "Processing [$($RepositoryInformation.CurrentCommit)..$($RepositoryChange.CurrentCommit)]"
            Write-Verbose -Message "RepositoryChange [$RepositoryChangeJSON]"
            $ReturnInformationJSON = Group-RepositoryFile -Files $RepositoryChange.Files `
                                                          -RepositoryInformation $RepositoryInformation
            $ReturnInformation = ConvertFrom-JSON -InputObject $ReturnInformationJSON
            Write-Verbose -Message "ReturnInformation [$ReturnInformationJSON]"
            Foreach($RunbookFilePath in $ReturnInformation.ScriptFiles)
            {
                Publish-SMARunbookChange -FilePath $RunbookFilePath `
                                         -CurrentCommit $RepositoryChange.CurrentCommit `
                                         -RepositoryName $RepositoryName
                Checkpoint-Workflow
            }
            Foreach($SettingsFilePath in $ReturnInformation.SettingsFiles)
            {
                Publish-SMASettingsFileChange -FilePath $SettingsFilePath `
                                              -CurrentCommit $RepositoryChange.CurrentCommit `
                                              -RepositoryName $RepositoryName
                Checkpoint-Workflow
            }
            foreach($Module in $ReturnInformation.ModuleFiles)
            {
                $ModuleName = (Test-ModuleManifest -Path $Module).Name
                $PowerShellModuleInformation = Import-SmaPowerShellModule -ModuleName $ModuleName `
                                                                          -WebserviceEndpoint $CIVariables.WebserviceEndpoint `
                                                                          -WebservicePort $CIVariables.WebservicePort `
                                                                          -Credential $SMACred
                SetAutomationModuleActivityMetadata -ModuleName $PowerShellModuleInformation.ModuleName `
                                                    -ModuleVersion $PowerShellModuleInformation.Version
                Checkpoint-Workflow
            }
            
            if($ReturnInformation.CleanRunbooks)
            {
                Remove-SmaOrphanRunbook -RepositoryName $RepositoryName
                Checkpoint-Workflow
            }
            if($ReturnInformation.CleanAssets)
            {
                Remove-SmaOrphanAsset -RepositoryName $RepositoryName
                Checkpoint-Workflow
            }
            if($ReturnInformation.CleanModules)
            {
                Remove-SmaOrphanModule
                Checkpoint-Workflow
            }
            if($ReturnInformation.ModuleFiles)
            {
                $RepositoryModulePath = "$($RepositoryInformation.Path)\$($RepositoryInformation.PowerShellModuleFolder)"
                inlinescript
                {
                    Add-PSEnvironmentPathLocation -Path $Using:RepositoryModulePath
                } -PSComputerName $RunbookWorker -PSCredential $SMACred
                Checkpoint-Workflow
            }
            $UpdatedRepositoryInformation = (Set-SmaRepositoryInformationCommitVersion -RepositoryInformation $CIVariables.RepositoryInformation `
                                                                                      -RepositoryName $RepositoryName `
                                                                                      -Commit $RepositoryChange.CurrentCommit) -as [string]
            $VariableUpdate = Set-SmaVariable -Name 'SMAContinuousIntegration-RepositoryInformation' `
                                              -Value $UpdatedRepositoryInformation `
                                              -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                              -Port $CIVariables.WebservicePort `
                                              -Credential $SMACred
            
            Write-Verbose -Message "Finished Processing [$($RepositoryInformation.CurrentCommit)..$($RepositoryChange.CurrentCommit)]"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}

# SIG # Begin signature block
# MIIOfQYJKoZIhvcNAQcCoIIObjCCDmoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUofTp4tou9jT+Cy3je0FZ1qk4
# 02+gggqQMIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# CisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBTmcCgH
# PN6//1Pkb+S49axeJyQy2zANBgkqhkiG9w0BAQEFAASBgHAq6AdZ9+mlAGoU0l0H
# XVUItjwOfN3FgYWWr1086/1cb5u8VQ5Q+SRt002vnrdRD+rmhFWycGR4D2qdpKMh
# 0RvavitpxASwho++UlOJyHo8d3jnZOzfgbMMDjnE+jiNQ3ymNccUB1RbLUg8Xf9g
# CtbmBWpClY8yfvRiO0ixKaDSoYICCzCCAgcGCSqGSIb3DQEJBjGCAfgwggH0AgEB
# MHIwXjELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9u
# MTAwLgYDVQQDEydTeW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0g
# RzICEA7P9DjI/r81bgTYapgbGlAwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJAzEL
# BgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1MDMxNjIwMTcwMFowIwYJKoZI
# hvcNAQkEMRYEFL7isWpKEb76HEJgOP52ix2HPXZkMA0GCSqGSIb3DQEBAQUABIIB
# AF9SXn1nwO30pmAfptMBStLVchHo9aIKhyGsfA+CerOLmQDiQtoySQsHd7fWSzG9
# d7MtOz36ZafIlCDETHOu31uiAksxOeRexXbTUlGi9MjKhEEmz8cXEou2iUfB+yva
# cpr45w5o1TG0jsqCo4nQLinQekYm0lpKMU4zMrbIliC13EN+YKnqGYrgMg+1BqEh
# +uVul02H5QCVvQso5ugf2tAMW9ohR3hz9KRx2Vi+gSlIifMSRN2yNeTOsE6lGDx9
# AwOHjCsbN0HKaAwQZ6u+UO9YdZK1z+WAYc/87lsbEQL/btzMoBcpUjSicWKUo/6O
# EHcclCFqaky1+WginLA87T0=
# SIG # End signature block
