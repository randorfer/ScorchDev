<#
.SYNOPSIS
    Examines paths for old files that match the specified criteria. The list of
    files discovered is returned.

.PARAMETER Path
    The paths that should be examined for old files.

.PARAMETER MaxAgeInDays
    The maximum age of files to keep, in days. Files that have not been modified
    at least this recently will be returned.

.PARAMETER Filter
    A file name filter that limits what files are returned. For example,
    specifying "*.ps1" would list only files whose extension is ps1.
    By default, there is no filter - all old files will be returned.

.PARAMETER Recurse
    If $True, recurse into subdirectories of the provided paths. By default,
    recursion is disabled.

.PARAMETER ComputerName
    The name of the computer to remote to in order to examine the paths. If local
    paths are specified (e.g. C:\Temp), this parameter is mandatory. May also be
    useful to limit bandwidth consumption over WAN links.

.PARAMETER CredentialName
    The name of the SMA credential to use for when searching for old files.
#>
workflow Get-OldFile
{
    param(
        [Parameter(Mandatory = $True)]  [String[]] $Path,
        [Parameter(Mandatory = $True)]  [Int] $MaxAgeInDays,
        [Parameter(Mandatory = $False)] [String] $Filter,
        [Parameter(Mandatory = $False)] [Switch] $Recurse,
        [Parameter(Mandatory = $False)] [String] $ComputerName,
        [Parameter(Mandatory = $False)] [String] $CredentialName
    )

    if(-not (Test-IsNullOrEmpty -String $CredentialName))
    {
        $Credential = Get-AutomationPSCredential -Name $CredentialName
    }
    else
    {
        $Credential = $null
    }
    $GroomableFiles = InlineScript
    {
        $Path = $Using:Path
        $Filter = $Using:Filter
        $MaxAgeInDays = $Using:MaxAgeInDays
        $Recurse = $Using:Recurse
        $ComputerName = $Using:ComputerName
        $Credential = $Using:Credential

        if($ComputerName -eq $null)
        {
            foreach($_Path in $Path)
            {
                if(-not (Test-UncPath -String $Path))
                {
                    Throw-Exception -Type 'NonUNCPathWithNullComputerName' `
                    -Message 'If a local path is provided, you must also specify a computer name' `
                    -Property @{
                        'Path' = $_Path
                    }
                }
            }
        }
        $GetChildItemParameters = @{
            'Path'  = $Path
            'File'  = $True
            'Force' = $True
            'Recurse' = $Recurse
        }
        if($Filter)
        {
            $GetChildItemParameters['Filter'] = $Filter
        }
        $InvokeCommandParameters = Get-OptionalRemotingParameter -ComputerName $ComputerName -Credential $Credential
        Invoke-Command @InvokeCommandParameters -ArgumentList $GetChildItemParameters, $MaxAgeInDays `
        -ScriptBlock `
        {
            $GetChildItemParameters, $MaxAgeInDays = $Args
            $OldestDate = (Get-Date).AddDays([Math]::Abs($MaxAgeInDays) * -1)
            Get-ChildItem @GetChildItemParameters | Where-Object -FilterScript {
                $_.LastWriteTime -lt $OldestDate 
            }
        }
    }
    return $GroomableFiles
}

# SIG # Begin signature block
# MIIOfQYJKoZIhvcNAQcCoIIObjCCDmoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU9hVqWMK7uZA3+goq3EC27v03
# EYGgggqQMIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# CisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQIx97j
# 3AWt0E14T8jkV7W+Hx0T8TANBgkqhkiG9w0BAQEFAASBgC6ndrAqtiCIDf6YFkc+
# YUqpr7U/ijGwsHBVXBpZkqIROiphEPwEhqbB+IPXWXTdnekqnl6cz6RefuTCoLqj
# ra4sFmudjT1i08YfHSQuZsRFUysvPPrpBk8oPuqkcS84kdqYWua5T+pX/vmE8gWF
# eXYsDNpG/LeRION4DtDXxE/SoYICCzCCAgcGCSqGSIb3DQEJBjGCAfgwggH0AgEB
# MHIwXjELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9u
# MTAwLgYDVQQDEydTeW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0g
# RzICEA7P9DjI/r81bgTYapgbGlAwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJAzEL
# BgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1MDMxNjIwMTYyNVowIwYJKoZI
# hvcNAQkEMRYEFFRZLpzPgr2c98r8pqfINnY9jQWDMA0GCSqGSIb3DQEBAQUABIIB
# AJRw3SZZ+vOWPFOBa6ZWZhnfomb4PB9W/QFZwKETjvEytrz7GC9FtHABlFUTjFGa
# 5mWxifP+t0U2eSWcpHNI+Wa6YXuCvm9OaJc6E9tnhZap6Q7WEkff8jc/c3TXb38h
# S3YCClH4A8RVQwGgU9Pxrw35A+1Ky/PJdyMXs0BKiuDTRaMUxHbtI4EelsMOI/7Q
# Zau56dJuA1G2QNlIlxSlzH9CC7OYa4BrsXfV3PUQ69YxHhekB0XDH+iolr7UxOLm
# F6tJsn5GbxL6bDuOVlRzzFDeiFS/n1C4my8YcHQVBFb6GJmGfOHPih1SshQodPkD
# LQHdC/szkxbix17WVrfO61A=
# SIG # End signature block
