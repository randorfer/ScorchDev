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
        [Parameter(Mandatory = $True)]
        $Exception,

        [Parameter(Mandatory = $False)]
        [ValidateSet('Debug', 'Error', 'Verbose', 'Warning')]
        $Stream = 'Warning'
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
        [Parameter(Mandatory = $True, ParameterSetName = 'Values')]
        [String]
        $Type,
        
        [Parameter(Mandatory = $True, ParameterSetName = 'Values')]
        [String]
        $Message,
        
        [Parameter(Mandatory = $False, ParameterSetName = 'Values')]
        [Hashtable]
        $Property = @{},

        [Parameter(Mandatory = $True, ParameterSetName = 'ExceptionInfo')]
        [Object]
        $ExceptionInfo
    )
    if($ExceptionInfo)
    {
        $Property = @{}
        ($ExceptionInfo |
            Get-Member |
            Where-Object -FilterScript {
                $_.MemberType -eq 'NoteProperty' 
        }).Name | ForEach-Object -Process `
        {
            $Property[$_] = $ExceptionInfo."$_"
        }
    }
    else
    {
        $Property = $Property.Clone()
        $Property['__CUSTOM_EXCEPTION__'] = $True
        $Property['Type'] = $Type
        $Property['FullyQualifiedErrorId'] = $Type
        $Property['Message'] = $Message
        $Property['InnerException'] = $null
    }
    return ($Property | ConvertTo-Json -Compress)
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
    Param(
        [Parameter(Mandatory = $True)]
        [Object]
        $Exception
    )
    
    $ExceptionString = New-Object -TypeName 'System.Text.StringBuilder'

    $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
    while($null -ne $ExceptionInfo)
    {
        # NoteProperty properties contain all the properties from the exception that
        # we care about, so filter on those.
        #
        # We also need to filter out the InnerException property, since nested exceptions
        # will be handled by the outer loop.
        $ExceptionInfo |
        Get-Member |
        Where-Object -FilterScript {
            $_.MemberType -eq 'NoteProperty' 
        } |
        Where-Object -FilterScript {
            $_.Name -ne 'InnerException' 
        } |
        ForEach-Object -Process {
            $PropertyName = $_.Name
            if(-not [String]::IsNullOrEmpty($ExceptionInfo."$PropertyName"))
            {
                $null = $ExceptionString.AppendLine("$PropertyName = $($ExceptionInfo."$PropertyName")")
            }
        }
        if($ExceptionInfo.InnerException)
        {
            $null = $ExceptionString.AppendLine('')
            $null = $ExceptionString.AppendLine('Which was raised from:')
            $null = $ExceptionString.AppendLine('')
        }
        $ExceptionInfo = $ExceptionInfo.InnerException
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
    Param(
        [Parameter(
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [AllowNull()]
        [Object]
        $Exception
    )

    $Property = @{}
    $TopLevelExceptionInfo = $null
    $PreviousExceptionInfo = $null
    while($null -ne $Exception)
    {
        $CustomException = Select-CustomException -Exception $Exception 
        if($CustomException)
        {
            $ExceptionInfo = ConvertFrom-Json -InputObject $CustomException
        }
        else
        {
            # Properties which should be included in the human-readable exception string.
            # The hash key is the identifier that will be used in the output string for the
            # hash value.
            #
            # Values will only be included if they are not null.
            $Property = @{
                'Type' = $Exception.GetType().FullName -replace '^Deserialized\.', ''
                'Message' = Select-FirstValid -Value @($Exception.Message,$Exception.Exception.Message,$Exception.InnerException.Message,$Exception.SerializedRemoteException.Message)
                'FullyQualifiedErrorId' = $Exception.FullyQualifiedErrorId
                'HResult' = $Exception.HResult
                'ScriptBlock' = Select-FirstValid -Value @($Exception.SerializedRemoteInvocationInfo.MyCommand.ScriptBlock,$Exception.InvocationInfo.MyCommand.ScriptBlock)
                'PositionMessage' = Select-FirstValid -Value @($Exception.SerializedRemoteInvocationInfo.PositionMessage,$Exception.InvocationInfo.PositionMessage)
                'ScriptStackTrace' = $Exception.ScriptStackTrace
                'StackTrace' = $Exception.StackTrace
                'InnerException' = $null
            }
            $ExceptionInfo = New-Object -TypeName 'PSObject' -Property $Property
        }

        if(-not $TopLevelExceptionInfo)
        {
            $TopLevelExceptionInfo = $ExceptionInfo
        }
        elseif($PreviousExceptionInfo)
        {
            $PreviousExceptionInfo.InnerException = $ExceptionInfo
        }

        $PreviousExceptionInfo = $ExceptionInfo
        $Exception = Select-FirstValid -Value $Exception.Exception, 
                                              $Exception.InnerException
    }
    try
    {
        Add-Member -InputObject $TopLevelExceptionInfo `
                   -MemberType NoteProperty `
                   -Name 'PSCallStack' `
                   -Value ((Get-PSCallStack) | Where-Object -FilterScript { $_.ScriptName -notlike '*-Exception.psm1' } | ConvertTo-JSON)
    }
    catch
    {
        Write-Debug -Message 'Error adding call stack'
    }
    return $TopLevelExceptionInfo
}

<#
.SYNOPSIS
    Tests whether or not the exception is a custom exception as returned
    by New-Exception or thrown by Throw-Exception. If it is, returns the
    custom exception string. Otherwise it returns $False.

.PARAMETER Exception
    The exception which should be tested.
#>
Function Select-CustomException
{
    param(
        [Parameter(Mandatory = $True)]
        [Object]
        $Exception
    )

    $TestString = @(($Exception -as [String]), ($Exception.Message -as [String]))
    
    Foreach($_TestString in $TestString)
    {
        try
        {
            $ExceptionObject = ConvertFrom-Json -InputObject $_TestString
            if($ExceptionObject.'__CUSTOM_EXCEPTION__')
            {
                return $_TestString
            }
        }
        catch [System.ArgumentException]
        {
            Write-Debug -Message 'Non custom error found'
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
    need to do $Exception.InnerException or $Exception.InnerException. InnerException
    to get what you want).

    This cmdlet attempts to remove the crud by filtering out select exception types.

.PARAMETER RootException
    The exception that was thrown by an invoked script block.
#>
Function Select-RelevantException
{
    Param(
        [Parameter(Mandatory = $True)]
        $RootException
    )
    $InnerException = $RootException.Exception
    $BlacklistedExceptions = [System.Management.Automation.ErrorRecord],
                             [System.Management.Automation.MethodInvocationException],
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
Function New-ThrownException
{
    param(
        [Parameter(Mandatory = $True, ParameterSetName = 'Values')]
        [String]
        $Type,

        [Parameter(Mandatory = $True, ParameterSetName = 'Values')]
        [String]
        $Message,

        [Parameter(Mandatory = $False, ParameterSetName = 'Values')]
        [Hashtable]
        $Property = @{},

        [Parameter(Mandatory = $True, ParameterSetName = 'ExceptionInfo')]
        [Object]
        $ExceptionInfo
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
Set-Alias -Name Throw-Exception -Value New-ThrownException
Export-ModuleMember -Function * -Alias * -Verbose:$False