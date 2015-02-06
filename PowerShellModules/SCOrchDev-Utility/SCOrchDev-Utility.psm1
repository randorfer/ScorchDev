<#
.SYNOPSIS
    Converts an object into a text-based represenation that can easily be written to logs.

.DESCRIPTION
    Format-ObjectDump takes any object as input and converts it to a text string with the 
    name and value of all properties the object's type information.  If the property parameter
    is supplied, only the listed properties will be included in the output.

.PARAMETER InputObject
    The object to convert to a textual representation.

.PARAMETER Property
    An optional list of property names that should be displayed in the output. 
#>
Function Format-ObjectDump
{
    [CmdletBinding()]
    Param([Parameter(Position=0, Mandatory=$True,ValueFromPipeline=$True)] [Object]$InputObject,
          [Parameter(Position=1, Mandatory=$False)] [string[]] $Property=@("*"))
    $typeInfo = $inputObject.GetType() | Out-String;
    $objList = $inputObject | Format-List -Property $property | Out-String;

    return "$typeInfo`r`n$objList"
}
<#
.SYNOPSIS
    Converts an input string into a boolean value.

.DESCRIPTION
    $values = @($null, [String]::Empty, "True", "False", 
                "true", "false", "    true    ", "0", 
                "1", "-1", "-2", '2', "string", 'y', 'n'
                'yes', 'no', 't', 'f');
    foreach ($value in $values) 
    {
        Write-Verbose -Message "[$($Value)] Evaluated as [`$$(ConvertTo-Boolean -InputString $value)]" -Verbose
    }                                     

    VERBOSE: [] Evaluated as [$False]
    VERBOSE: [] Evaluated as [$False]
    VERBOSE: [True] Evaluated as [$True]
    VERBOSE: [False] Evaluated as [$False]
    VERBOSE: [true] Evaluated as [$True]
    VERBOSE: [false] Evaluated as [$False]
    VERBOSE: [   true   ] Evaluated as [$True]
    VERBOSE: [0] Evaluated as [$False]
    VERBOSE: [1] Evaluated as [$True]
    VERBOSE: [-1] Evaluated as [$True]
    VERBOSE: [-2] Evaluated as [$True]
    VERBOSE: [2] Evaluated as [$True]
    VERBOSE: [string] Evaluated as [$True]
    VERBOSE: [y] Evaluated as [$True]
    VERBOSE: [n] Evaluated as [$False]
    VERBOSE: [yes] Evaluated as [$True]
    VERBOSE: [no] Evaluated as [$False]
    VERBOSE: [t] Evaluated as [$True]
    VERBOSE: [f] Evaluated as [$False]

.PARAMETER InputString
    The string value to convert
#>
Function ConvertTo-Boolean
{
    Param($InputString)

    if(-not [System.String]::IsNullOrEmpty($InputString))
    {
        $res    = $true
        $success = [bool]::TryParse($InputString,[ref]$res)
        if($success)
        { 
            return $res
        }
        else
        {
            $InputString = ([string]$InputString).ToLower()
    
            Switch ($InputString)
            {
                'f'     { $false }
                'false' { $false }
                'off'   { $false }
                'no'    { $false }
                'n'     { $false }
                default
                {
                    try
                    {
                        return [bool]([int]$InputString)
                    }
                    catch
                    {
                        return [bool]$InputString
                    }
                }
            }
        }
    }
    else
    {
        return $false
    }
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
        If($FilterScript.InvokeWithContext($Null, (Get-Variable -Name '_'), $Null))
        {
            Return $_
        }
    }
    Return $Null
}

<#
.SYNOPSIS
    A wrapper around [String]::IsNullOrWhiteSpace.

.DESCRIPTION
    Provides a PowerShell function wrapper around [String]::IsNullOrWhiteSpace,
    since PowerShell Workflow will not allow a direct method call.

.PARAMETER String
    The string to pass to [String]::IsNullOrWhiteSpace.
#>
Function Test-IsNullOrWhiteSpace
{
    Param([Parameter(Mandatory=$True)][AllowNull()] $String)
    Return [String]::IsNullOrWhiteSpace($String)
}

<#
.SYNOPSIS
    A wrapper around [String]::IsNullOrEmpty.

.DESCRIPTION
    Provides a PowerShell function wrapper around [String]::IsNullOrEmpty,
    since PowerShell Workflow will not allow a direct method call.

.PARAMETER String
    The string to pass to [String]::IsNullOrEmpty.
#>
Function Test-IsNullOrEmpty
{
    Param([Parameter(Mandatory=$True)][AllowNull()] $String)
    Return [String]::IsNullOrEmpty($String)
}
Export-ModuleMember -Function *