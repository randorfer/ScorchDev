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
        $Property['Type'] = $Type
        $Property['Message'] = $Message
    }
    $PropertyList = @('__CUSTOM_EXCEPTION__')
    foreach($P in $Property.GetEnumerator())
    {
        $PropertyList += @($P.Name, ($P.Value.ToString()))
    }
    return ($PropertyList -join "`0")
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
    Given a list of values, returns the first value that is valid according to $FilterScript.

.DESCRIPTION
    Select-FirstValid iterates over each value in the list $Value. Each value is passed to
    $FilterScript as $_. If $FilterScript returns true, the value is considered valid and
    will be returned if no other value has been already. If $FilterScript returns false,
    the value is deemed invalid and the next element in $Value is checked.

    If no elements in $Value are valid, returns $Null.

.PARAMETER Value
    A list of values to check for validity.

.PARAMETER FilterScript
    A script block that determines what values are valid. Elements of $Value can be referenced
    by $_. By default, values are simply converted to Bool.
#>
Function Select-FirstValid
{
    # Don't allow values from the pipeline. The pipeline does weird things with
    # nested arrays.
    Param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$False)] [AllowNull()] $Value,
        [Parameter(Mandatory=$False)] $FilterScript = { $_ -As [Bool] }
    )
    ForEach($_ in $Value)
    {
        If($FilterScript.InvokeWithContext($Null, @(Get-Variable -Name '_'), $Null))
        {
            Return $_
        }
    }
    Return $Null
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
        $Fields = $CustomException.Split("`0")
        # Find the indices of the array where there are property names.
        #
        # The first field is our custom exception magic string, so that is excluded.
        # After that, every other index is a property name.
        $PropertyIndicies = (1..($Fields.Count - 1)) | Where-Object { ($_ % 2) -eq 1 }
        foreach($Index in $PropertyIndicies)
        {
            $PropertyName = $Fields[$Index]
            $PropertyValue = $Fields[$Index + 1]
            $Property[$PropertyName] = $PropertyValue
        }
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
        if($TestString.Split("`0")[0] -eq '__CUSTOM_EXCEPTION__')
        {
            return $TestString
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
        switch -CaseSensitive (Get-ExceptionType -Exception $_)
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

Export-ModuleMember -Function *