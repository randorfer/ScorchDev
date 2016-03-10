#requires -Version 2
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
    An optional list of property names that should be displayed in the output!
#>
Function Format-ObjectDump
{
    [CmdletBinding()]
    [OutputType([string])]
    Param(
        [Parameter(Position = 0, Mandatory = $True,ValueFromPipeline = $True)]
        [Object]$InputObject,
        [Parameter(Position = 1, Mandatory = $False)] [string[]] $Property = @('*')
    )
    $typeInfo = $InputObject.GetType() | Out-String
    $objList = $InputObject | `
        Format-List -Property $Property | `
        Out-String

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
    [OutputType([string])]
    Param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [AllowNull()]
        [string]
        $InputString
    )

    if(-not [System.String]::IsNullOrEmpty($InputString))
    {
        $res    = $True
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
                'f'     
                {
                    $False 
                }
                'false' 
                {
                    $False 
                }
                'off'   
                {
                    $False 
                }
                'no'    
                {
                    $False 
                }
                'n'     
                {
                    $False 
                }
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
        return $False
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
        [Parameter(Mandatory = $True, ValueFromPipeline = $False)]
        [AllowNull()]
        $Value,

        [Parameter(Mandatory = $False)]
        $FilterScript = {
            $_ -As [Bool] 
        }
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
    Param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [String]
        $Path
    )
    $RunbookPaths = Get-ChildItem -Path $Path -Include '*.ps1' -Recurse

    $DeclaredCommandMap = @{}
    foreach ($Path in $RunbookPaths) 
    {
        $Tokens = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Path $Path), [ref] $Null)
        For($i = 0 ; $i -lt $Tokens.Count - 1 ; $i++)
        {
            $Token = $Tokens[$i]
            if($Token.Type -eq 'Keyword' -and $Token.Content -in @('function', 'workflow'))
            {
                Write-Debug -Message "Found command $($NextToken.Content) in $Path of type $($Token.Content)"
                $NextToken = $Tokens[$i+1]
                $DeclaredCommandMap."$($NextToken.Content)" = @{
                    'Path' = $Path
                    'Type' = $Token.Content
                }
            }
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
    [OutputType([bool])]
    Param([Parameter(Mandatory = $True, ValueFromPipeline = $True)]
    [AllowNull()]
    $String)
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
    [OutputType([bool])]
    Param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [AllowNull()]
        $String
    )
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
    [OutputType([hashtable])] 
    Param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)] 
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory = $False)]
        [System.Management.Automation.PSMemberTypes]
        $MemberType = [System.Management.Automation.PSMemberTypes]::NoteProperty,

        [Parameter(Mandatory = $False)]
        [ScriptBlock] 
        $KeyFilterScript = {
            Param($KeyName) $KeyName 
        }
    ) 
    
    $outputObj = @{}   
    
    foreach($KeyName in ($InputObject | Get-Member -MemberType $MemberType).Name) 
    {
        $KeyName = Invoke-Command -ScriptBlock $KeyFilterScript -ArgumentList $KeyName
        if(-not (Test-IsNullOrEmpty -String $KeyName))
        {
            if($outputObj.ContainsKey($KeyName))
            {
                $outputObj += $InputObject."$KeyName"
            }
            else
            {
                $Null = $outputObj.Add($KeyName, $InputObject."$KeyName")
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
    [OutputType([hashtable])]
    Param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory = $True)][string]
        
        $KeyName,
        [Parameter(Mandatory = $False)][ScriptBlock]
        $KeyFilterScript = {
            Param($Key) $Key 
        }
    )
    $outputObj = @{}
    foreach($Object in $InputObject)
    {
        $Key = $Object."$KeyName"
        $Key = Invoke-Command -ScriptBlock $KeyFilterScript -ArgumentList $Key
        if(-not (Test-IsNullOrEmpty -String $Key))
        {
            if($outputObj.ContainsKey($Key))
            {
                $outputObj[$Key] += $Object
            }
            else
            {
                $Null = $outputObj.Add($Key, @($Object))
            }
        }
    }
    return $outputObj
}
<#
    .Synopsis
    Updates the local powershell environment path. Sets the target path as a part
    of the environment path if it does not already exist there
    
    .Parameter Path
    The path to add to the system environment variable 'path'. Only adds if it is not already there            
#>
Function Add-PSEnvironmentPathLocation
{
    Param(
        [Parameter(
            Mandatory = $True,
            ValueFromPipeline = $True,
            Position = 0

        )]
        $Path,

        [Parameter(
            Mandatory = $False,
            ValueFromPipeline = $True,
            Position = 1
        )]
        [System.EnvironmentVariableTarget]
        $Location = [System.EnvironmentVariableTarget]::User
    )
    
    $CurrentPSModulePath = [System.Environment]::GetEnvironmentVariable('PSModulePath', $Location) -as [string]
    if(-not($CurrentPSModulePath.ToLower().Contains($Path.ToLower())))
    {
        Write-Verbose -Message "The path [$Path] was not in the environment path [$CurrentPSModulePath]. Adding."
        if($CurrentPSModulePath -as [bool])
        {
            [Environment]::SetEnvironmentVariable( 'PSModulePath', "$CurrentPSModulePath;$Path", $Location )
        }
        else
        {
            [Environment]::SetEnvironmentVariable( 'PSModulePath', "$Path", $Location )
        }

    }
}
<#
    .Synopsis
        Looks for the tag workflow in a file and returns the next string
    
    .Parameter FilePath
        The path to the file to search
#>
Function Get-WorkflowNameFromFile
{
    Param([Parameter(Mandatory=$true)][string] $FilePath)

    $DeclaredCommands = Find-DeclaredCommand -Path $FilePath
    Foreach($Command in $DeclaredCommands.Keys)
    {
        if($DeclaredCommands.$Command.Type -eq 'Workflow') 
        { 
            return $Command -as [string]
        }
    }

    Throw-Exception -Type 'NoWorkflowDefined' -Message 'No workflow defined in file'
}

<#
    .Synopsis
        Tests to see if a file has a PS workflow defined inside of it
    
    .Parameter FilePath
        The path to the file to search
#>
Function Test-FileIsWorkflow
{
    Param([Parameter(Mandatory=$true)][string] $FilePath)

    try { Get-WorkflowNameFromFile -FilePath $FilePath }
    catch
    {
        $Exception = $_
        $ExceptionInformation = Get-ExceptionInfo -Exception $Exception
        Switch ($ExceptionInformation.FullyQualifiedErrorId)
        {
            'NoWorkflowDefined' { return $false }
        }
    }
    return $true
}

<#
    .Synopsis
        Gets a script name based on the filename
    
    .Parameter FilePath
        The path to the file
#>
Function Get-ScriptNameFromFileName
{
    Param([Parameter(Mandatory=$true)][string] $FilePath)
    $CompletedParams = Write-StartingMessage -Stream Debug

    $MatchRegex = '([^\.]+)' -as [string]
    $FileInfo = Get-Item -Path $FilePath
    if($FileInfo.Name -match $MatchRegex)
    {
        Return $Matches[1]
    }
    else
    {
        Throw-Exception -Type 'CouldNotDetermineName' -Message 'Could not determine the script name'
    }

    Write-CompletedMessage @CompletedParams
}

<#
    .Synopsis
        Gets a script name based on the filename
    
    .Parameter FilePath
        The path to the file
#>
Function Get-DSCConfigurationName
{
    Param([Parameter(Mandatory=$true)][string] $FilePath)
    $CompletedParams = Write-StartingMessage -Stream Debug

    $MatchRegex = 'Configuration[\s]+([^{\s]+)[\s]*' -as [string]
    $FileContent = (Get-Content $FilePath) -as [string]
    if($FileContent -Match $MatchRegex)
    {
        $Name = $Matches[1]
    }
    else
    {
        Throw-Exception -Type 'CouldNotDetermineName' -Message 'Could not determine the configuration name'
    }

    Write-CompletedMessage @CompletedParams -Status $Name
    Return $Name
}

<#
    .Synopsis
        Gets a script name based on the filename
    
    .Parameter FilePath
        The path to the file
#>
Function Get-DSCNodeName
{
    Param([Parameter(Mandatory=$true)][string] $FilePath)
    $CompletedParams = Write-StartingMessage -Stream Debug

    $MatchRegex = 'Node[\s]+([^{\s]+)[\s]*' -as [regex]
    $FileContent = (Get-Content $FilePath) -as [string]
    $Match = $MatchRegex.Matches($FileContent)
    $ReturnObj = $Match | ForEach-Object { ($_.Groups[1].Value.Replace('''','')).Replace('"','') }
    
    Write-CompletedMessage @CompletedParams -Status ($ReturnObj | ConvertTo-Json)
    Return $ReturnObj
}

<#
.SYNOPSIS
    Given a hashtable, filters entries based on their value. Returns
    a new hashtable whose elements are only those whose value cause
    $FilterScript to return $True.

.PARAMETER Hashtable
    The hashtable to filter.

.PARAMETER FilterScript
    The filter script to apply to each element of the hashtable.
#>
Function Select-Hashtable
{
    param(
        [Parameter(Mandatory=$True)]  [Hashtable] $Hashtable,
        [Parameter(Mandatory=$False)] [ScriptBlock] $FilterScript = { $_ -as [Bool] }
    )

    $FilteredHashtable = @{}
    foreach($Element in $Hashtable.GetEnumerator())
    {
        $_ = $Element.Value
        if($FilterScript.InvokeWithContext($null, (Get-Variable -Name '_'), $null))
        {
            $FilteredHashtable[$Element.Name] = $Element.Value
        }
    }
    return $FilteredHashtable
}
<#
.Synopsis
    Writes a finished verbose message
#>
function Write-CompletedMessage
{
    Param(
        [Parameter(Mandatory=$True)]
        [datetime]
        $StartTime,

        [Parameter(Mandatory=$True)]
        [String]
        $Name,

        [Parameter(Mandatory=$False)]
        [String]
        $Status = $Null,

        [Parameter(Mandatory=$False)]
        [ValidateSet('Debug', 'Error', 'Verbose', 'Warning')]
        [String]
        $Stream = 'Verbose',

        [Parameter(Mandatory=$False)]
        [switch]
        $PassThru
    )
    
    if($Name -notmatch '^\[.*]$')
    {
        $Name = "[$Name]"
    }
    if($Status -as [bool])
    {
        $Name = "$Name [$Status]"
    } 
    $LogCommand = (Get-Command -Name "Write-$Stream")
    $EndTime = Get-Date
    $ElapsedTime = ($EndTime - $StartTime).TotalSeconds
    $Message = "Completed $Name in [$($ElapsedTime)] Seconds"
    & $LogCommand -Message $Message `
                  -WarningAction Continue

    if($PassThru.IsPresent)
    {
        Write-Output -InputObject @{
            'Name' = $Name
            'StartTime' = $StartTime
            'EndTime' = $EndTime
            'ElapsedTime' = $ElapsedTime
            'Message' = $Message
        }
    }
}

<#
.Synopsis
    Writes the standard starting message
.Parameter String
    An additional string to write out
.Parameter Stream
    The stream to write the starting message to
#>
function Write-StartingMessage
{
    Param(
        [Parameter(Mandatory=$False)]
        [String]
        $CommandName = '',

        [Parameter(Mandatory=$False)]
        [String]
        $String = '',

        [Parameter(Mandatory=$False)]
        [ValidateSet('Debug', 'Error', 'Verbose', 'Warning')]
        [String]
        $Stream = 'Verbose'
    )
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $_CommandName = Select-FirstValid $Commandname, ((Get-PSCallStack)[1].Command -as [string])
    $Name = [string]::Empty
    if($_CommandName -as [bool])
    {
        if($String -as [bool])
        {
            $Name = "[$_CommandName] [$String]"
        }
        else
        {
            $Name = "[$_CommandName]"
        }
    }
    elseif($String -as [bool])
    {
        $Name = "[$String]"
    }
    else
    {
        $ExceptionMessage = 'Could not determine the current name. 
                             Please pass the -string parameter with 
                             $WorkflowCommandName if running from workflow' -replace "`r`n", ' ' -replace '  ', ''
        Throw-Exception -Type 'CannotDetermineName' `
                        -Message $ExceptionMessage
    }

    $LogCommand = (Get-Command -Name "Write-$Stream")
    & $LogCommand -Message "Starting $Name" `
                  -WarningAction Continue `
                  -ErrorAction Continue
    
    Return @{ 'Name' = $Name ; 'StartTime' = (Get-Date) ; 'Stream' = $Stream}
}
Function Start-SleepUntil
{
    Param(
        [Parameter(Mandatory=$False)]
        [DateTime]
        $DateTime = (Get-Date).AddSeconds(1)
    )
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParams = Write-StartingMessage -String "DateTime [$DateTime]"
    $SleepSeconds = ($DateTime - (Get-Date)).TotalSeconds
    if($SleepSeconds -gt 0)
    {
        Write-Verbose -Message "Sleeping for [$SleepSeconds] seconds"
        Start-Sleep -Seconds $SleepSeconds
    }
    Write-CompletedMessage @CompletedParams
}

<#
.Synopsis
    Generates one or more complex strings designed to fulfill the requirements for Active Directory

.DESCRIPTION
    Generates one or more complex strings designed to fulfill the requirements for Active Directory

.EXAMPLE
    New-RandomString
    C&3SX6Kn

    Will generate one password with a length between 8  and 12 chars.
.EXAMPLE
    New-RandomString -MinLength 8 -MaxLength 12 -Count 4
    7d&5cnaB
    !Bh776T"Fw
    9"C"RxKcY
    %mtM7#9LQ9h

    Will generate four passwords, each with a length of between 8 and 12 chars.
.EXAMPLE
    New-RandomString -InputString abc, ABC, 123 -Length 4
    3ABa

    Generates a password with a length of 4 containing atleast one char from each InputString
.EXAMPLE
    New-RandomString -InputString abc, ABC, 123 -Length 4 -FirstChar abcdefghijkmnpqrstuvwxyzABCEFGHJKLMNPQRSTUVWXYZ
    3ABa

    Generates a password with a length of 4 containing atleast one char from each InputString that will start with a letter from 
    the string specified with the parameter FirstChar
.OUTPUTS
    [String]
.FUNCTIONALITY
    Generates random strings
#>
Function New-RandomString
{
    [CmdletBinding(DefaultParameterSetName='FixedLength',ConfirmImpact='None')]
    [OutputType([String])]
    Param
    (
        # Specifies minimum length
        [Parameter(
            Mandatory=$false,
            ParameterSetName='RandomLength'
        )]
        [ValidateScript({$_ -gt 0})]
        [Alias('Min')] 
        [int]
        $MinLength = 8,
        
        # Specifies maximum length
        [Parameter(
            Mandatory=$false,
            ParameterSetName='RandomLength'
        )]
        [ValidateScript({
            if($_ -ge $MinPasswordLength) { $true }
            else { Throw 'Max value cannot be lesser than min value.' }
        })]
        [Alias('Max')]
        [int]
        $MaxLength = 12,

        # Specifies a fixed length
        [Parameter(
            Mandatory=$false,
            ParameterSetName='FixedLength'
        )]
        [ValidateRange(1,2147483647)]
        [int]
        $Length = 8,
        
        # Specifies an array of strings containing charactergroups from which the password will be generated.
        # At least one char from each group (string) will be used.
        [String[]]
        $InputString = @(
            'abcdefghijkmnpqrstuvwxyz',
            'ABCEFGHJKLMNPQRSTUVWXYZ',
            '23456789',
            '!"#%&'
        ),

        # Specifies a string containing a character group from which the first character in the password will be generated.
        # Useful for systems which requires first char in password to be alphabetic.
        [String]
        $FirstChar,
        
        # Specifies number of passwords to generate.
        [ValidateRange(1,2147483647)]
        [int]
        $Count = 1
    )
    Begin 
    {
        Function Get-Seed
        {
            # Generate a seed for randomization
            $RandomBytes = New-Object -TypeName 'System.Byte[]' 4
            $Random = New-Object -TypeName 'System.Security.Cryptography.RNGCryptoServiceProvider'
            $Random.GetBytes($RandomBytes)
            [BitConverter]::ToUInt32($RandomBytes, 0)
        }
    }
    Process
    {
        $CompletedParams = Write-StartingMessage
        For($iteration = 1;$iteration -le $Count; $iteration++)
        {
            $Password = @{}
            # Create char arrays containing groups of possible chars
            [char[][]]$CharGroups = $InputString

            # Create char array containing all chars
            $AllChars = $CharGroups | ForEach-Object {[Char[]]$_}

            # Set password length
            if($PSCmdlet.ParameterSetName -eq 'RandomLength')
            {
                if($MinLength -eq $MaxLength) {
                    # If password length is set, use set length
                    $Length = $MinLength
                }
                else {
                    # Otherwise randomize password length
                    $Length = ((Get-Seed) % ($MaxLength + 1 - $MinLength)) + $MinLength
                }
            }

            # If FirstChar is defined, randomize first char in password from that string.
            if($PSBoundParameters.ContainsKey('FirstChar')){
                $Password.Add(0,$FirstChar[((Get-Seed) % $FirstChar.Length)])
            }
            # Randomize one char from each group
            Foreach($Group in $CharGroups) {
                if($Password.Count -lt $Length) {
                    $Index = Get-Seed
                    While ($Password.ContainsKey($Index)){
                        $Index = Get-Seed                        
                    }
                    $Password.Add($Index,$Group[((Get-Seed) % $Group.Count)])
                }
            }

            # Fill out with chars from $AllChars
            for($i=$Password.Count;$i -lt $Length;$i++) {
                $Index = Get-Seed
                While ($Password.ContainsKey($Index)){
                    $Index = Get-Seed                        
                }
                $Password.Add($Index,$AllChars[((Get-Seed) % $AllChars.Count)])
            }
            $RetObj = $(-join ($Password.GetEnumerator() | Sort-Object -Property Name | Select-Object -ExpandProperty Value))
            Write-Output -InputObject $RetObj
        }
        Write-CompletedMessage @CompletedParams -Status $RetObj
    }
}
Export-ModuleMember -Function * -Verbose:$False -Debug:$False