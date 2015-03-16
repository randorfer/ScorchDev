$SmaWebServiceDetails = @{
    'WebServiceEndpoint' = 'https://scorchsma01.scorchdev.com'
    'Port'             = 9090
    'AuthenticationType' = 'Windows'
}


# Uncomment this section and fill in $CredUsername and $CredPassword values
# to talk to SMA using Basic Auth instead of Windows Auth

# username / password of an account with access to the SMA Web Service
$CredUsername = 'scorchdev\sma'
$CredPassword = 'TechEd_2014'
    
$SecurePassword = $CredPassword | ConvertTo-SecureString -AsPlainText -Force
   
$SmaWebServiceDetails.AuthenticationType = 'Basic'
$SmaWebServiceDetails.Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($CredUsername, $SecurePassword)


function Get-AutomationAsset 
{
    param(
        [Parameter(Mandatory = $True)]
        [ValidateSet('Variable', 'Certificate', 'PSCredential', 'Connection')]
        [string] $Type,

        [Parameter(Mandatory = $True)]
        [string]$Name
    )

    $MaxSecondsToWaitOnJobCompletion = 600
    $SleepTime = 5
    $DoneJobStatuses = @('Completed', 'Failed', 'Stopped', 'Blocked', 'Suspended')

    # Call Get-AutomationAsset runbook in SMA to get the asset value in serialized form
    $Params = @{
        'Type' = $Type
        'Name' = $Name
    }

    $Job = Start-SmaRunbook -Name 'Get-AutomationAsset' -Parameters $Params @SmaWebServiceDetails

    if(!$Job) 
    {
        Write-Error -Message "Unable to start the 'Get-AutomationAsset' runbook. Make sure it exists and is published in SMA."
    }
    else 
    {
        # Wait for Get-AutomationAsset completion
        $TotalSeconds = 0
        $JobInfo = $null

        do 
        {
            Start-Sleep -Seconds $SleepTime
            $TotalSeconds += $SleepTime

            $JobInfo = Get-SmaJob -Id $Job @SmaWebServiceDetails
        }
        while((!$DoneJobStatuses.Contains($JobInfo.JobStatus)) -and ($TotalSeconds -lt $MaxSecondsToWaitOnJobCompletion))

        if($TotalSeconds -ge $MaxSecondsToWaitOnJobCompletion) 
        {
            Write-Error -Message "Timeout exceeded. 'Get-AutomationAsset' job $Job did not complete in $MaxSecondsToWaitOnJobCompletion seconds."
        }
        elseif($JobInfo.JobException) 
        {
            Write-Error ("'Get-AutomationAsset' job $Job threw exception: `n" + $JobInfo.JobException)
        }
        else 
        {
            $SerializedOutput = Get-SmaJobOutput -Id $Job -Stream Output @SmaWebServiceDetails
            
            $Output = [System.Management.Automation.PSSerializer]::Deserialize($SerializedOutput.StreamText)  

            $Output
        }
    }
}

function Get-AutomationConnection 
{
    param(
        [Parameter(Mandatory = $True)]
        [string] $Name
    )

    Get-AutomationAsset -Type Connection -Name $Name
}

function Set-AutomationVariable 
{
    param(
        [Parameter(Mandatory = $True)]
        [string] $Name,

        [Parameter(Mandatory = $True)]
        [object] $Value
    )

    $Variable = Get-SmaVariable -Name $Name @SmaWebServiceDetails

    if($Variable) 
    {
        if($Variable.IsEncrypted) 
        {
            $Output = Set-SmaVariable -Name $Name -Value $Value -Encrypted @SmaWebServiceDetails
        }
        else 
        {
            $Output = Set-SmaVariable -Name $Name -Value $Value -Force @SmaWebServiceDetails
        }
    }
}

function Get-AutomationCertificate 
{
    param(
        [Parameter(Mandatory = $True)]
        [string] $Name
    )

    $Thumbprint = Get-AutomationAsset -Type Certificate -Name $Name
    
    if($Thumbprint) 
    {
        $Cert = Get-Item -Path "Cert:\CurrentUser\My\$Thumbprint"

        $Cert
    }
}

# SIG # Begin signature block
# MIIOfQYJKoZIhvcNAQcCoIIObjCCDmoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUrWQeL3pg7m6bygUr9KkaoGrc
# 85igggqQMIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# CisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBSGjmsl
# f1GlDr2f8mYzCsXrMxVdZTANBgkqhkiG9w0BAQEFAASBgHq28SWnq9pAIQ+52WKz
# yn93jE9xmP0Bcnr1jTMNiKsHOGXwwJ+ywDl3fFadKr+IfKtJ1TGf6j/PHWhE7dEL
# CG1rqJTWPQ8q3mLyL2PNHXgmnuQPK4E0Kvs4MFNlD+ZiOOa4sxj2GH3KjzNTM0Hp
# tLQqHhM1iSR6d012v7BACTPqoYICCzCCAgcGCSqGSIb3DQEJBjGCAfgwggH0AgEB
# MHIwXjELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9u
# MTAwLgYDVQQDEydTeW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0g
# RzICEA7P9DjI/r81bgTYapgbGlAwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJAzEL
# BgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1MDMxNjIwMTMyMFowIwYJKoZI
# hvcNAQkEMRYEFF3ucQSlo7z4Tz+7Di+5msLheI+6MA0GCSqGSIb3DQEBAQUABIIB
# AJlYNb40W22UwLUxufZCfPCHClEkArQRqVo6Dgg/MjwyqMpdKGxh+khML/l3BHKi
# bNJpZhWGEbDwC88gEyWWikUV/FcP0v1RaLMW+0XaX1dJTo2iUfC/RNfJmRqB6UqN
# kCcjY14vkqL8CzyTeLpKJfRWjVm81xUjhjwnRq9q87/WYT+WpHR9AOo82PHmz5XC
# l1rkoil014tniv6V1ZOgflLs9RwUoAc7fMC1Oa7ofn2pu6oFThRWytv/5W56MPkM
# a0Y2ChR6ghhjSWdFMX5vP5aF4gq5y7a0qLwhqE0gY1rBC0v0Cj6qjtEdOn8q03KR
# 7/QaHDWZFuV+MuT6p56evKg=
# SIG # End signature block
