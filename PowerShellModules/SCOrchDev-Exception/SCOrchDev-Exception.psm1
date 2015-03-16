<#
.SYNOPSIS
    Logs the details of an exception to the specified stream.

.PARAMETER Exception
    The exception whose details should be logged.

.PARAMETER Stream
    The stream that the exception details should be logged to.
#>
Function Write-Exception
{
    Param(
        [Parameter(Mandatory=$True)]  $Exception,
        [Parameter(Mandatory=$False)] [ValidateSet('Debug', 'Error', 'Verbose', 'Warning')] $Stream = 'Error'
    )
    $LogCommand = (Get-Command -Name "Write-$Stream")
    $ExceptionString = Convert-ExceptionToString -Exception $Exception
    & $LogCommand -Message "Exception information`r`n------`r`n$ExceptionString" -ErrorAction Continue -WarningAction Continue

}


<#
.SYNOPSIS
    Returns a PSObject representing a custom exception.

.PARAMETER Type
    The "type" of the exception.

    This isn't actually the type. It's a string you can use to figure out what the type would be
    if PowerShell actually supported custom exceptions.

.PARAMETER Message
    A message describing the failure.

.PARAMETER Property
    A hashtable containing other properties to propogate with the exception. All values in the
    hash table will be converted to strings.

.EXAMPLE
    $Exception = New-Exception -Type 'GenericFailure' -Message 'Failing, just because'
    throw $Exception
#>
Function New-Exception
{
    param(
        [Parameter(Mandatory=$True, ParameterSetName='Values')]  [String] $Type,
        [Parameter(Mandatory=$True, ParameterSetName='Values')]  [String] $Message,
        [Parameter(Mandatory=$False, ParameterSetName='Values')] [Hashtable] $Property = @{},
        [Parameter(Mandatory=$True, ParameterSetName='ExceptionInfo')] [Object] $ExceptionInfo
    )
    if($ExceptionInfo)
    {
        $Property = @{}
        ($ExceptionInfo | Get-Member | Where-Object -FilterScript { $_.MemberType -eq 'NoteProperty' }).Name | ForEach-Object -Process `
        {
            $Property[$_] = $ExceptionInfo."$_"
        }
    }
    else
    {
        $Property = $Property.Clone()
        $Property['__CUSTOM_EXCEPTION__'] = $True
        $Property['Type'] = $Type
        $Property['Message'] = $Message
    }
    return ($Property | ConvertTo-JSON)
}

<#
.SYNOPSIS
    Converts an exception into a string suitable for reading, including
    as much detail as possible that is useful for troubleshooting.

.PARAMETER Exception
    The exception that should be converted to a string.
#>
Function Convert-ExceptionToString
{
    Param([Parameter(Mandatory=$True)]  $Exception)
    $CustomException = Select-CustomException -Exception $Exception
    $ExceptionString = New-Object -TypeName 'System.Text.StringBuilder'
    if($CustomException)
    {
        $ExceptionInfo = Get-ExceptionInfo -Exception $CustomException
        # NoteProperty properties contain all the properties from the exception that
        # we care about, so filter on those
        $ExceptionInfo | Get-Member | Where-Object { $_.MemberType -eq 'NoteProperty' } |
            ForEach-Object -Process `
            {
                $PropertyName = $_.Name
                $ExceptionString.AppendLine("$PropertyName = $($ExceptionInfo."$PropertyName")") | Out-Null
            }
    }
    else
    {
        # *sigh* PowerShell likes to wrap our exceptions in System.Management.Automation.ErrorRecord
        # nonsense, so we have to unwrap it here to get the real exception.
        $RealException = Select-FirstValid -Value $Exception.Exception, $Exception

        # Properties which should be included in the human-readable exception string.
        # The hash key is the identifier that will be used in the output string for the
        # hash value.
        #
        # Values will only be included if they are not null.
        $PropertiesToLog = @{
            'Type' = $RealException.GetType().FullName;
            'Message' = $RealException.Message;
            'ScriptBlock' = $RealException.SerializedRemoteInvocationInfo.MyCommand.ScriptBlock;
            'PositionMessage' = $RealException.SerializedRemoteInvocationInfo.PositionMessage;
        }
        foreach($Property in $PropertiesToLog.Keys)
        {
            if($PropertiesToLog[$Property] -ne $null)
            {
                $ExceptionString.AppendLine("$Property = $($PropertiesToLog[$Property])") | Out-Null
            }
        }
    }
    return $ExceptionString.ToString()
}

<#
.SYNOPSIS
    Returns the exception information for an exception.

.PARAMETER Exception
    The exception whose information should be returned.
#>
Function Get-ExceptionInfo
{
    param([Parameter(Mandatory=$True)] [Object] $Exception)

    $Property = @{}
    $CustomException = Select-CustomException -Exception $Exception 
    if($CustomException)
    {
        $ExceptionInfo = ConvertFrom-Json -InputObject $CustomException
    }
    else
    {
        # Calling GetType() on the exception doesn't return the actual type, it just
        # returns PSObject. Dumb.
        #
        # But the members returned by Get-Member have what we want, we just have to strip
        # off a leading "Deserialized."
        $Property['Type'] = (($Exception | Get-Member)[0].TypeName -replace '^Deserialized\.', '')
        $Property['Message'] = $Exception.Message
        $ExceptionInfo = New-Object -TypeName 'PSObject' -Property $Property
    }
    return (New-Object -TypeName 'PSObject' -Property $Property)
}

<#
.SYNOPSIS
    Tests whether or not the exception is a custom exception as returned
    by New-Exception or thrown by Throw-Exception. If it is, returns the
    custom exception string. Otherwise, returns $False.

.PARAMETER Exception
    The exception which should be tested.
#>
Function Select-CustomException
{
    param([Parameter(Mandatory=$True)] [Object] $Exception)

    foreach($Exc in @($Exception, $Exception.Exception, $Exception.SerializedRemoteException, $Exception.Message))
    {
        $TestString = ($Exc -as [String])
        try
        {
            $ExceptionObject = ConvertFrom-Json -InputObject $TestString
            if($ExceptionObject.'__GMI_CUSTOM_EXCEPTION__')
            {
                return $TestString
            }
        }
        catch [System.ArgumentException]
        {
            # It's not valid JSON, do nothing.
        }
    }
}

<#
.SYNOPSIS
    Attepts to select the relevant exception that has been thrown inside an invoked
    script block.

.DESCRIPTION
    Invoking a script block that throws an exception will result in an object where
    the exception we actually care about is hidden in an InnerException property.
    The exception of interest may not always be nested at the same depth (i.e. you may
    need to do $Exception.InnerException or $Exception.InnerException.InnerException
    to get what you want).

    This cmdlet attempts to remove the crud by filtering out select exception types.

.PARAMETER RootException
    The exception that was thrown by an invoked script block.
#>
Function Select-RelevantException
{
    Param([Parameter(Mandatory=$True)] $RootException)
    $InnerException = $RootException.Exception
    $BlacklistedExceptions = [System.Management.Automation.ErrorRecord], [System.Management.Automation.MethodInvocationException], `
                             [System.Management.Automation.CmdletInvocationException]
    While(($InnerException.GetType() -in $BlacklistedExceptions) -and $InnerException.InnerException)
    {
        $InnerException = $InnerException.InnerException
    }
    Return $InnerException
}
<#
.SYNOPSIS
    Throws a custom exception.

.PARAMETER Type
    The "type" of the exception.

    This isn't actually the type. It's a string you can use to figure out what the type would be
    if PowerShell actually supported custom exceptions. Damnit, PowerShell. Use a switch block
    or similar in your catch statement to work with this.

.PARAMETER Message
    A message describing the failure.

.EXAMPLE
    try
    {
        Throw-Exception -Type 'GenericFailure' -Message 'Failing, just because'
    }
    catch
    {
        switch -CaseSensitive ((Get-ExceptionInfo -Exception $_).Type)
        {
            'GenericFailure'
            {
                Write-Warning -Message 'Look, a generic failure'
            }
            'SomeOtherFailure'
            {
                Write-Warning -Message 'Look, a failure we will never see'
            }
            default
            {
                Write-Warning -Message 'I am handling ALL the failures!'
            }
        }
    }
#>
Function Throw-Exception
{
    param(
        [Parameter(Mandatory=$True, ParameterSetName='Values')]  [String] $Type,
        [Parameter(Mandatory=$True, ParameterSetName='Values')]  [String] $Message,
        [Parameter(Mandatory=$False, ParameterSetName='Values')] [Hashtable] $Property = @{},
        [Parameter(Mandatory=$True, ParameterSetName='ExceptionInfo')] [Object] $ExceptionInfo
    )
    if($ExceptionInfo)
    {
        throw New-Exception -ExceptionInfo $ExceptionInfo
    }
    else
    {
        throw New-Exception -Type $Type -Message $Message -Property $Property
    }
}

Export-ModuleMember -Function * -Verbose:$false
# SIG # Begin signature block
# MIIOfQYJKoZIhvcNAQcCoIIObjCCDmoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUAvv8xrEf/25aLVDlQvA/v/iz
# W+KgggqQMIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# CisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBR/Kjho
# n98y3oUQIuOC0mUXMpd54TANBgkqhkiG9w0BAQEFAASBgFMl8pkjJWxrJl5DMPOT
# 706NIsPp4g7Loo2czsBiwjd4n02ygJRYDInDs0MV4MLqakGzH00wA6Jp79uO4lSK
# oQj/GPue77h48I17PwSrUn/dIFzFSeMxVbYnOjB2QDxz+eCA/iCqXMIXQWf//f2P
# e2wbM2Mo9aPxNgDyLUfQa0MJoYICCzCCAgcGCSqGSIb3DQEJBjGCAfgwggH0AgEB
# MHIwXjELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9u
# MTAwLgYDVQQDEydTeW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0g
# RzICEA7P9DjI/r81bgTYapgbGlAwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJAzEL
# BgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1MDMxNjIwMDQzNlowIwYJKoZI
# hvcNAQkEMRYEFFfK02Uf1bL1rPFgpQXTfryq5V1UMA0GCSqGSIb3DQEBAQUABIIB
# ACkbWzw8YVKBbeBWSJtYIJyY3yMYHvvxg118SrsOx4318Cnfw3HIMi1Ra7bOE2e8
# WRVBvG+wMW0xtLxkvLKDjF0ijYIKmisP+RR3GnvKJsLpN7cr8WrF3xI8C2kGsMhf
# RBKq6wzeb6zCcI4YHhfTwF6UsK7Jhq9Yg2VXAvz3Nemz2tRXGBrmKjDalXLxHdpP
# JZGMvwWG91Do6tmJ+XcLonQiWcZVxu9YNwP0nxMUz4jnEywzN6gapQyNqJrAnYg4
# mojcn2onsft767mJsmUIQMCWmxMfgqxVTwMSaMuf4Sjk1KI2i6evELNRggq69svM
# c5t61ERtOrGcnOxhkyBZV4Y=
# SIG # End signature block
