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

.EXAMPLE
    $values = @($null, [String]::Empty, "True", "False", 
                "true", "false", "    true    ", "0", 
                "1", "-1", "-2", '2', "string", 'y', 'n'
                'yes', 'no', 't', 'f');
    foreach ($value in $values) 
    {
        Write-Verbose -Message "[$($Value)] Evaluated as [`$$(ConvertTo-Boolean $value)]" -Verbose
    }                                     

    VERBOSE: [] Evaluated as [$False]
    VERBOSE: [] Evaluated as [$False]
    VERBOSE: [True] Evaluated as [$True]
    VERBOSE: [False] Evaluated as [$False]
    VERBOSE: [true] Evaluated as [$True]
    VERBOSE: [false] Evaluated as [$False]
    VERBOSE: [    true    ] Evaluated as [$True]
    VERBOSE: [0] Evaluated as [$True]
    VERBOSE: [1] Evaluated as [$True]
    VERBOSE: [-1] Evaluated as [$True]
    VERBOSE: [-2] Evaluated as [$True]
    VERBOSE: [2] Evaluated as [$True]
    VERBOSE: [string] Evaluated as [$True]
    VERBOSE: [y] Evaluated as [$True]
    VERBOSE: [n] Evaluated as [$True]
    VERBOSE: [yes] Evaluated as [$True]
    VERBOSE: [no] Evaluated as [$True]
    VERBOSE: [t] Evaluated as [$True]
    VERBOSE: [f] Evaluated as [$True]

.EXAMPLE
    ConvertTo-Boolean a -FalseMatches @('a','b')
    False
    ConvertTo-Boolean b -FalseMatches @('a','b')
    False
    ConvertTo-Boolean ab -FalseMatches @('a','b')
    True

.PARAMETER InputObject
    The object value to convert

.PARAMETER FalseMatches
    An array to match against. If the input object is contained in the
    False Matches array false will be returned
#>
Function ConvertTo-Boolean
{
    Param([Parameter(Mandatory=$False)] $InputObject,
          [Parameter(Mandatory=$False)] [Array]$FalseMatches = @())
    
    if(-not [System.String]::IsNullOrEmpty($InputObject))
    {
        $res     = $true
        $success = [bool]::TryParse($InputObject,[ref]$res)
        if($success)
        { 
            return $res
        }
        else
        {
            $InputObjectString = $InputObject.ToString()
            if($FalseMatches -contains $InputObjectString)
            {
                return $False
            }
            else
            {
                return [bool]$InputObject
            }
        }
    }
    else
    {
        return $false
    }
}
Export-ModuleMember -Function *