$Script:LocalAutomationVariable = @{}
<#
.SYNOPSIS
    Returns a scriptblock that, when dot-sourced, will import a workflow and all its dependencies.

.DESCRIPTION
    Import-Workflow is a helper function to resolve dependencies of a given workflow. It must be
    invoked with a very specific syntax in order to import workflows into your current session.
    See the example.

.PARAMETER WorkflowName
    The name of the workflow to import.

.PARAMETER Path
    The path containing all ps1 files to search for workflow dependencies.

.EXAMPLE
    PS > . (Import-Workflow Test-Workflow)
#>
function Import-Workflow 
{
    param(
        [Parameter(Mandatory=$True)]  [String] $WorkflowName,
        [Parameter(Mandatory=$False)] [String] $Path = $env:AutomationWorkflowPath
    )

    # TODO: Make $CompileStack a more appropriate data structure.
    # We're not really using the stack functionality at all. In fact,
    # it was buggy. :-(
    $CompileStack = New-Object -TypeName 'System.Collections.Stack'
    $TokenizeStack = New-Object -TypeName 'System.Collections.Stack'
    $DeclaredCommands = Find-DeclaredCommand -Path $Path
    $BaseWorkflowPath = $DeclaredCommands[$WorkflowName].Path
    $Stacked = @{$BaseWorkflowPath = $True}
    $TokenizeStack.Push($BaseWorkflowPath)
    $CompileStack.Push($BaseWorkflowPath)
    while ($TokenizeStack.Count -gt 0) 
    {
        $ScriptPath = $TokenizeStack.Pop()
        $Tokens = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Path $ScriptPath), [ref] $null)
        $NeededCommands = ($Tokens | Where-Object -FilterScript { $_.Type -eq 'Command' }).Content
        foreach ($Command in $NeededCommands) 
        {
            $NeededScriptPath = $DeclaredCommands[$Command].Path
            # If $NeededScriptPath is $null, we didn't find it when we searched declared
            # commands in the runbook path. We'll assume that is okay and that the command
            # is provided by some other means (e.g. a module import)
            if (($NeededScriptPath -ne $null) -and (-not $Stacked[$NeededScriptPath])) 
            {
                $TokenizeStack.Push($NeededScriptPath)
                $CompileStack.Push($NeededScriptPath)
                $Stacked[$NeededScriptPath] = $True
            }
        }
    }
    $WorkflowDefinitions = ($CompileStack | foreach { (Get-Content -Path $_) }) -join "`n"
    $ScriptBlock = [ScriptBlock]::Create($WorkflowDefinitions)
    return $ScriptBlock
}

<#
.SYNOPSIS
    Returns the named automation variable, referencing local JSON files to find values.

.PARAMETER Name
    The name of the variable to retrieve.
#>
Function Get-AutomationVariable
{
    Param(
        [Parameter(Mandatory=$True)]
        [String]
        $Name 
    )
    
    If(-not $Script:LocalAutomationVariable.ContainsKey($Name))
    {
        Update-LocalAutomationVariable
        If(-not $Script:LocalAutomationVariable.ContainsKey($Name))
        {
            Write-Warning -Message "Couldn't find variable $Name" -WarningAction 'Continue'
            Throw-Exception -Type 'VariableDoesNotExist' `
                            -Message "Couldn't find variable $Name" `
                            -Property @{
                'Variable' = $Name;
            }
        }
    }
    Return ($Script:LocalAutomationVariable[$Name]).Value
}
function Update-LocalAutomationVariable
{
    param()

    Write-Verbose -Message 'Updating variables in memory'
    $FilesToProcess = (Get-ChildItem -Path $env:AutomationGlobalsPath -Include '*.json' -Recurse).FullName
    Read-SmaJSONVariables -Path $FilesToProcess
}

<#
.SYNOPSIS
    Processes an JSON file, caching any variables it finds.

.PARAMETER Path
    The JSON files that should be processed.
#>
Function Read-SmaJSONVariables
{
    Param(
        [Parameter(Mandatory=$True)]
        [AllowNull()]
        [String[]]
        $Path
    )

    $Script:LocalAutomationVariable = @{}
    ForEach($_Path in $Path)
    {
        Try
        {
            $JSON = ConvertFrom-JSON -InputObject ((Get-Content -Path $_Path) -as [String])
        }
        Catch
        {
            Write-Warning -Message "Could not process [$_Path] - variables from that file will not be available" -WarningAction 'Continue'
            Write-Warning -Message "Does [$_Path] contain malformed JSON?" -WarningAction 'Continue'
            Write-Exception -Exception $_ -Stream 'Warning'
        }
        if(-not (Test-IsNullOrEmpty $JSON.Variables))
        {
            ForEach($VariableName in ($JSON.Variables | Get-Member -MemberType NoteProperty).Name)
            {
                $Var = $JSON.Variables."$VariableName"
                $retVar = New-Object -TypeName 'PSObject' -Property @{ 'Name' = $VariableName; 'Value' = $var.Value }
                $Script:LocalAutomationVariable[$VariableName] = $retVar
            }
        }
    }
}
<#
    .Synopsis
        Creates a variable in a json file. When this is commited these
        variables will be created in SMA through continuous integration

    .Parameter VariableFilePath
        The path to the file to store this variable in. If not passed it is
        assumed you want to store it in the same file you did last time

    .Parameter Name
        The name of the variable to create. 
        Variables will be named in the format

        Prefix-Name

    .Parameter Prefix
        The prefix of the variable to create. If not passed it will default
        to the name of the variable file you are storing it in
        Variables will be named in the format

        Prefix-Name
    
    .Parameter Value
        The value to store in the object. If a non primative is passed it
        will be converted into a string using convertto-json

    .Parameter Description
        The description of the variable to store in SMA

    .isEncrypted
        A boolean flag representing if this value should be encrypted in SMA

#>
Function Set-AutomationVariable
{
    Param(
        [Parameter(Mandatory=$True)]  $Name,
        [Parameter(Mandatory=$True)]  $Value,
        [Parameter(Mandatory=$False)] $Prefix = [System.String]::Empty,
        [Parameter(Mandatory=$False)] $Description = [System.String]::Empty,
        [Parameter(Mandatory=$False)] $isEncrypted = $False
    )
    if(-not $Prefix)
    {
        $Prefix = $Name.Split('-')[0]
    }
    else
    {
        $Name = "$Prefix-$Name"
    }
    $SettingsFilePath = "$($Env:AutomationGlobalsPath)\$($Prefix).json"
    if(-not (Test-Path -Path $SettingsFilePath))
    {
        New-Item -ItemType File `
                 -Path $settingsFilePath
    }

    $SettingsVars = ConvertFrom-JSON -InputObject ((Get-Content -Path $SettingsFilePath) -as [String])
    if(-not $SettingsVars) { $SettingsVars = @{} }
    else
    {
        $SettingsVars = ConvertFrom-PSCustomObject $SettingsVars
    }
    if(-not $SettingsVars.ContainsKey('Variables'))
    {
        $SettingsVars.Add('Variables',@{}) | out-null
    }
    
    if($Value.GetType().Name -notin @('Int32','String','DateTime'))
    {
        $Value = ConvertTo-JSON $Value -Compress
    }

    if($SettingsVars.Variables.GetType().name -eq 'PSCustomObject') { $SettingsVars.Variables = ConvertFrom-PSCustomObject $SettingsVars.Variables }
    if($SettingsVars.Variables.ContainsKey($Name))
    {
        $SettingsVars.Variables."$Name".Value = $Value
        if($Description) { $SettingsVars.Variables."$Name".Description = $Description }
        if($Encrypted)   { $SettingsVars.Variables."$Name".Encrypted   = $Encrypted   }
    }
    else
    {
        $SettingsVars.Variables.Add(
            $Name, @{ 
                'Value' = $Value ;
                'Description' = $Description ;
                'isEncrypted' = $isEncrypted 
            }
        )
    }
    
    Set-Content -Path $SettingsFilePath -Value (ConvertTo-JSON $SettingsVars) -Encoding UTF8
    Read-SmaJSONVariables $SettingsFilePath
}

Function Remove-AutomationVariable
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]        
        $Name,

        [Parameter(Mandatory=$False)]
        [string]
        $Prefix
    )
    if(-not $Prefix)
    {
        $Prefix = $Name.Split('-')[0]
    }
    else
    {
        $Name = "$Prefix-$Name"
    }
    $SettingsFilePath = "$($Env:AutomationGlobalsPath)\$($Prefix).json"
    if(-not (Test-Path $SettingsFilePath))
    {
        Throw-Exception -Type 'SettingsFileNotFound' `
                        -Message 'Could not find the settings file for the target variable.' `
                        -Property @{
                            'SettingsFilePath' = $SettingsFilePath ;
                            'VariableName' = $Name ;
                            'VariablePrefix' = $Prefix ;
                        }
    }
    $SettingsVars = ConvertFrom-JSON -InputObject ((Get-Content -Path $SettingsFilePath) -as [String])
    if(-not $SettingsVars) { $SettingsVars = @{} }
    else
    {
        $SettingsVars = ConvertFrom-PSCustomObject $SettingsVars
    }
    if(-not $SettingsVars.ContainsKey('Variables'))
    {
        $SettingsVars.Add('Variables',@{}) | out-null
    }

    if($SettingsVars.Variables.GetType().name -eq 'PSCustomObject') { $SettingsVars.Variables = ConvertFrom-PSCustomObject $SettingsVars.Variables }
    if($SettingsVars.Variables.ContainsKey($Name))
    {
        $SettingsVars.Variables.Remove($Name)
        Set-Content -Path $SettingsFilePath -Value (ConvertTo-JSON $SettingsVars) -Encoding UTF8
        Read-SmaJSONVariables $SettingsFilePath
    }
    else
    {
        Write-Warning (New-Exception -Type 'Variable Not found' `
                                     -Message 'The variable was not found in the current variable file.' `
                                     -Property @{ 'VariableName' = $Name ;
                                                  'CurrentFilePath' = $SettingsFilePath ;
                                                  'VariableJSON' = $SettingsVars }) `
                      -WarningAction 'Continue'
    }
}
Workflow Get-AutomationPSCredential 
{
    [OutputType([System.Management.Automation.PSCredential])]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $Name
    )

    Try
    {
        $Credential = (Get-PasswordVaultCredential -UserName $Name -AsPSCredential)
        Write-Verbose -Message "Credential [$Name] found in PasswordVault"
        if(($Credential -as [array]).count -gt 1)
        {
            Write-Verbose -Message "Found more than 1 [$(($Credential -as [array]).count)] objects. Using the first"
            $Credential = $Credential[0]
        }
    }
    Catch
    {
        Throw-Exception -Type 'CredentialNotFound' `
                        -Message 'Could not find credential. Please set it up in the local password vault using Set-PasswordVaultCredential' `
                        -Property @{ 
                            'Name' = $Name 
                        }
    }
    Return $Credential -as [System.Management.Automation.PSCredential]
}

Function Set-AutomationSchedule
{
    Param(
        [Parameter(Mandatory=$True)]
        [String]
        $Name,

        [Parameter(Mandatory=$False)]
        [String]
        $Prefix = [System.String]::Emptpy,
        
        [Parameter(Mandatory=$False)]
        [String]
        $Description = [System.String]::Emptpy,

        [Parameter(Mandatory=$False)]
        [DateTime]
        $NextRun = $null,

        [Parameter(Mandatory=$False)]
        [DateTime]
        $ExpirationTime = $null,

        [Parameter(Mandatory=$False)]
        [Int]
        $DayInterval = $null,

        [Parameter(Mandatory=$False)]
        [String]
        $RunbookName = [System.String]::Emptpy,

        [Parameter(Mandatory=$False)]
        [HashTable]
        $Parameter = @{}
    )
    if(-not $Prefix)
    {
        $Prefix = $Name.Split('-')[0]
    }
    else
    {
        $Name = "$Prefix-$Name"
    }
    $SettingsFilePath = "$($Env:AutomationGlobalsPath)\$($Prefix).json"
    if(-not (Test-Path -Path $SettingsFilePath))
    {
        New-Item -ItemType File `
                 -Path $settingsFilePath
    }

    $SettingsVars = ConvertFrom-JSON -InputObject ((Get-Content -Path $SettingsFilePath) -as [String])
    if(-not $SettingsVars) { $SettingsVars = @{} }
    else
    {
        $SettingsVars = ConvertFrom-PSCustomObject $SettingsVars
    }

    if(-not $SettingsVars.ContainsKey('Schedules'))
    {
        $SettingsVars.Add('Schedules',@{}) | out-null
    }
    if($SettingsVars.Schedules.GetType().name -eq 'PSCustomObject') { $SettingsVars.Schedules = ConvertFrom-PSCustomObject $SettingsVars.Schedules }
    if($SettingsVars.Schedules.ContainsKey($Name))
    {
        if($Description)    { $SettingsVars.Schedules."$Name".Description    = $Description }
        if($NextRun)        { $SettingsVars.Schedules."$Name".NextRun        = $NextRun }
        if($ExpirationTime) { $SettingsVars.Schedules."$Name".ExpirationTime = $ExpirationTime }
        if($DayInterval)    { $SettingsVars.Schedules."$Name".DayInterval    = $DayInterval }
        if($RunbookName)    { $SettingsVars.Schedules."$Name".RunbookName    = $RunbookName }
        if($Parameter)      { $SettingsVars.Schedules."$Name".Parameter      = $(ConvertTo-Json $Parameter) }
    }
    else
    {
        if(-not $ExpirationTime -or
           -not $NextRun -or
           -not $DayInterval -or
           -not $RunbookName )
        {
            Throw-Exception -Type 'MinimumNewParametersNotFound' `
                            -Message 'The minimum set of input parameters for creating a new schedule was not supplied. Look at nulls' `
                            -Property @{ 'Name' = $Name ;
                                         'ExpirationTime' = $ExpirationTime ;
                                         'NextRun' = $NextRun ;
                                         'DayInterval' = $DayInterval ;
                                         'RunbookName' = $RunbookName ; }
        }

        $SettingsVars.Schedules.Add(
            $Name, @{ 
                'Description' = $Description ;
                'ExpirationTime' = $ExpirationTime -as [DateTime] ;
                'NextRun' = $NextRun -as [DateTime] ;
                'DayInterval' = $DayInterval ;
                'RunbookName' = $RunbookName ;
                'Parameter' = $(ConvertTo-JSON $Parameter)
            }
        )
    }
    
    Set-Content -Path $SettingsFilePath -Value (ConvertTo-JSON $SettingsVars) -Encoding UTF8
}
Function Remove-AutomationSchedule
{
    Param(
        [Parameter(Mandatory=$False)]
        $SettingsFilePath,

        [Parameter(Mandatory=$True)] 
        $Name,

        [Parameter(Mandatory=$False)]
        $Prefix
    )
    if(-not $Prefix)
    {
        $Prefix = $Name.Split('-')[0]
    }
    $SettingsFilePath = "$($Env:AutomationGlobalsPath)\$($Prefix).json"
    if(-not (Test-Path $SettingsFilePath))
    {
        Throw-Exception -Type 'SettingsFileNotFound' `
                        -Message 'Could not find the settings file for the target variable.' `
                        -Property @{
                            'SettingsFilePath' = $SettingsFilePath ;
                            'ScheduleName' = $Name ;
                            'SchedulePrefix' = $Prefix ;
                        }
    }
    $SettingsVars = ConvertFrom-JSON -InputObject ((Get-Content -Path $SettingsFilePath) -as [String])
    if(Test-IsNullOrEmpty $SettingsVars.Schedules)
    {
        Add-Member -InputObject $SettingsVars -MemberType NoteProperty -Value @() -Name Schedules
    }
    if(($SettingsVars.Schedules | Get-Member -MemberType NoteProperty).Name -Contains $Name)
    {
        $SettingsVars.Schedules = $SettingsVars.Schedules | Select-Object -Property * -ExcludeProperty $Name
        Set-Content -Path $SettingsFilePath -Value (ConvertTo-JSON $SettingsVars) -Encoding UTF8
    }
    else
    {
        Write-Warning (New-Exception -Type 'Schedule Not found' `
                                     -Message 'The schedule was not found in the current variable file. Try specifiying the file' `
                                     -Property @{ 'VariableName' = $Name ;
                                                  'CurrentFilePath' = $SettingsFilePath ;
                                                  'SettingsJSON' = $SettingsVars }) `
                      -WarningAction 'Continue'
    }
}
<#
    .Synopsis
        Fake for Set-AutomationActivityMetadata for local dev.
#>
Function Set-AutomationActivityMetadata
{
    Param([Parameter(Mandatory=$True)] $ModuleName,
          [Parameter(Mandatory=$True)] $ModuleVersion,
          [Parameter(Mandatory=$True)] $ListOfCommands)

    $Inputs = ConvertTo-JSON @{ 'ModuleName' = $ModuleName;
                                'ModuleVersion' = $ModuleVersion;
                                'ListOfCommands' = $ListOfCommands }
    Write-Verbose -Message "$Inputs"
}
Export-ModuleMember -Function * -Verbose:$false