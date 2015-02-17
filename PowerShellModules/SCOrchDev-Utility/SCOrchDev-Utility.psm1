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
    Returns a dictionary mapping the name of a PowerShell command to the file containing its
    definition.

.DESCRIPTION
    Find-DeclaredCommand searches $Path for .ps1 files. Each .ps1 is tokenized in order to
    determine what functions and workflows are defined in it. This information is used to
    return a dictionary mapping the command name to the file in which it is defined.

.PARAMETER Path
    The path to search for command definitions.
#>
function Find-DeclaredCommand
{
    param(
        [Parameter(Mandatory=$True)] [String] $Path
    )
    $RunbookPaths = Get-ChildItem -Path $Path -Include '*.ps1' -Recurse

    $DeclaredCommandMap = @{}
    foreach ($Path in $RunbookPaths) {
        $Tokens = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Path $Path), [ref] $null)
        $PreviousCommand = $null
        $DeclaredCommands = ($Tokens | Where-Object -FilterScript {
            ($_.Type -eq 'CommandArgument') -and ($PreviousCommand.Content -in ('function', 'workflow'))
            $PreviousCommand = $_
        }).Content
        foreach ($DeclaredCommand in $DeclaredCommands) {
            Write-Debug -Message "Found command $DeclaredCommand in $Path"
            $DeclaredCommandMap[$DeclaredCommand] = $Path
        }
    }
    return $DeclaredCommandMap
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
<#
    .Synopsis
        Takes a pscustomobject and converts into a IDictionary.
        Translates all membertypes into keys for the IDictionary
    
    .Parameter InputObject
        The input pscustomobject object to convert

    .Parameter MemberType
        The membertype to change into a key property

    .Parameter KeyFilterScript
        A script to run to manipulate the keyname during grouping.
#>
Function ConvertFrom-PSCustomObject
{ 
    Param([Parameter(Mandatory=$True)] 
          $InputObject,
          [Parameter(Mandatory=$False)][System.Management.Automation.PSMemberTypes]
          $MemberType = [System.Management.Automation.PSMemberTypes]::NoteProperty,
          [Parameter(Mandatory=$False)][ScriptBlock] 
          $KeyFilterScript = { Param($KeyName) $KeyName } ) 
    
    $outputObj = @{}   
    
    foreach($KeyName in ($InputObject | Get-Member -MemberType $MemberType).Name) 
    {
        $KeyName = Invoke-Command $KeyFilterScript -ArgumentList $KeyName
        if(-not (Test-IsNullOrEmpty $KeyName))
        {
            if($outputObj.ContainsKey($KeyName))
            {
                $outputObj += $InputObject."$KeyName"
            }
            else
            {
                $outputObj.Add($KeyName, $InputObject."$KeyName") | Out-Null 
            } 
        }
    } 
    return $outputObj 
} 

<#
    .Synopsis
        Converts an object or array of objects into a hashtable
        by grouping them by the target key property
    
    .Parameter InputObject
        The object or array of objects to convert

    .Parameter KeyName
        The name of the property to group the objects by

    .Parameter KeyFilterScript
        A script to run to manipulate the keyname during grouping.
#>
Function ConvertTo-Hashtable
{
    Param([Parameter(Mandatory=$True)]
          $InputObject,
          [Parameter(Mandatory=$True)][string]
          $KeyName,
          [Parameter(Mandatory=$False)][ScriptBlock]
          $KeyFilterScript = { Param($Key) $Key })
    $outputObj = @{}
    foreach($Object in $InputObject)
    {
        $Key = $Object."$KeyName"
        $Key = Invoke-Command $KeyFilterScript -ArgumentList $Key
        if(-not (Test-IsNullOrEmpty $Key))
        {
            if($outputObj.ContainsKey($Key))
            {
                $outputObj[$Key] += $Object
            }
            else
            {
                $outputObj.Add($Key, @($Object)) | Out-Null
            }
        }
    }
    return $outputObj
}

<#
    .Synopsis
        Creates a zip file from a target directory
    
    .Parameter SourceDir
        The directory to zip up

    .Parameter ZipFilePath
        The path to store the new zip file at

    .Parameter OverwriteExisting
        If the zip file already exists should it be overwritten. Default: True
#>
Function New-ZipFile
{
    Param([Parameter(Mandatory=$true) ][string] $SourceDir,
          [Parameter(Mandatory=$true) ][string] $ZipFilePath,
          [Parameter(Mandatory=$false)][bool]   $OverwriteExisting = $true)
            
    $null = $(
        Write-Verbose -Message "Starting New-ZipFile"
        Write-Verbose -Message "`$SourceDir [$SourceDir]"
        Write-Verbose -Message "`$ZipFilePath [$ZipFilePath]"
                
        if($OverwriteExisting)
        {
            if(Test-Path -Path $ZipFilePath)
            {
                Remove-Item $ZipFilePath -Force -Confirm:$false
            }
        }

        if(-not (Test-Path -Path "$($ZipFilePath.Substring(0,$ZipFilePath.LastIndexOf('\')))"))
        {
            $newDir = New-Item -ItemType Directory `
                                -Path "$($ZipFilePath.Substring(0,$ZipFilePath.LastIndexOf('\')))" `
                                -Force `
                                -Confirm:$false
        }

        Add-Type -Assembly System.IO.Compression.FileSystem
        $CompressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
        [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceDir, $ZipFilePath, $CompressionLevel, $false)
        Write-Verbose -Message "Finished New-ZipFile"
    )
}
<#
    .Synopsis
        Creates a new empty temporary directory
    
    .Parameter Root
        The root path to create the temporary directory under
#>
Function New-TempDirectory
{
    Param([Parameter(Mandatory=$false) ][string] $SourceDir = "C:\")
    
    do
    {
        $TempDirectory   = "$($SourceDir)\$([System.Guid]::NewGuid())"
        $DirectoryExists = Test-Path -Path $TempDirectory
    }
    while($DirectoryExists)

    New-Item -ItemType Directory $TempDirectory
}
Export-ModuleMember -Function * -Verbose:$false -Debug:$false