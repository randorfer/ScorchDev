$Script:LocalSMAVariableLastUpdate = (Get-Date)
$Script:LocalSMAVariables = $null
$Script:CurrentSettingsFile = $null
$env:LocalSMAVariableWarn = Select-FirstValid -Value $env:LocalSMAVariableWarn, $true -FilterScript { $_ -ne $null }

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
        [Parameter(Mandatory=$False)] [String] $Path = $env:SMARunbookPath
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
    Returns the named automation variable, referencing local XML files to find values.

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

    $LocalSMAVariableWarn = ConvertTo-Boolean -InputString (Select-FirstValid -Value $env:LocalSMAVariableWarn, 'True' -FilterScript { $_ -ne $null })
    # Check to see if local variables are overridden in the environment - if so, pull directly from SMA.
    if((-not (Test-IsNullOrEmpty $env:AutomationWebServiceEndpoint)) -and (-not $env:LocalAuthoring))
    {
        if($LocalSMAVariableWarn)
        {
            Write-Warning -Message "Getting variable [$Name] from endpoint [$env:AutomationWebServiceEndpoint]"
        }
        # FIXME: Don't hardcode credential name.
        $Var = Get-SMAVariable -Name $Name -WebServiceEndpoint $env:AutomationWebServiceEndpoint
        return $Var
    }

    if($LocalSMAVariableWarn)
    {
        Write-Warning -Message "Getting variable [$Name] from local JSON"
    }
    If(Test-UpdateLocalAutomationVariable)
    {
        Update-LocalAutomationVariable
    }
    If(-not $Script:LocalSMAVariables.ContainsKey($Name))
    {
        Write-Warning -Message "Couldn't find variable $Name" -WarningAction 'Continue'
        Write-Warning -Message 'Do you need to update your local variables? Try running Update-LocalAutomationVariable.'
        Throw-Exception -Type 'VariableDoesNotExist' `
                        -Message "Couldn't find variable $Name" `
                        -Property @{
            'Variable' = $Name;
        }
    }
    Return $Script:LocalSMAVariables[$Name]
}

function Test-UpdateLocalAutomationVariable
{
    param( )

    $UpdateInterval = Select-FirstValid -Value ([Math]::Abs($env:LocalSMAVariableUpdateInterval)), 10 `
                                        -FilterScript { $_ -ne $null }
    if(Test-IsNullOrEmpty $Script:LocalSMAVariables)
    {
        return $True
    }
    elseif($UpdateInterval -eq 0)
    {
        return $False
    }
    elseif((Get-Date).AddSeconds(-1 * $UpdateInterval) -gt $Script:LocalSMAVariableLastUpdate)
    {
        return $True
    }
    return $False
}

function Update-LocalAutomationVariable
{
    param()

    Write-Verbose -Message 'Updating variables in memory'
    $Script:LocalSMAVariableLastUpdate = Get-Date
    $FilesToProcess = (Get-ChildItem -Path $env:SMAGlobalsPath -Include '*.json' -Recurse).FullName
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
        [Parameter(Mandatory=$True)]  [AllowNull()] [String[]] $Path
    )

    $Script:LocalSMAVariables = @{}
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
                $Script:LocalSMAVariables[$VariableName] = $retVar
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
Function Set-LocalDevAutomationVariable
{
    Param(
        [Parameter(Mandatory=$False)] $SettingsFilePath,
        [Parameter(Mandatory=$True)]  $Name,
        [Parameter(Mandatory=$True)]  $Value,
        [Parameter(Mandatory=$False)] $Prefix = [System.String]::Empty,
        [Parameter(Mandatory=$False)] $Description = [System.String]::Empty,
        [Parameter(Mandatory=$False)] $isEncrypted = $False
        )
    if(-not $SettingsFilePath)
    {
        if(-not $Script:CurrentSettingsFile)
        {
            Throw-Exception -Type 'Variable File Not Set' `
                            -Message 'The variable file path has not been set'
        }
        $SettingsFilePath = $Script:CurrentSettingsFile
    }
    else
    {
        if($Script:CurrentSettingsFile -ne $SettingsFilePath)
        {
            Write-Warning -Message "Setting Default Variable file to [$SettingsFilePath]" `
                          -WarningAction 'Continue'
            $Script:CurrentSettingsFile = $SettingsFilePath
        }
    }

    if(Test-IsNullOrEmpty $Prefix)
    {
        if($SettingsFilePath -Match '.*\\(.+)\.json$')
        {
            $Prefix = $Matches[1]
        }
        else
        {
            Throw-Exception -Type 'UndeterminableDefaultPrefix' `
                            -Message 'Could not determine what the default prefix should be' `
                            -Property @{ 'SettingsFilePath' = $SettingsFilePath }
        }
    }

    if($Name -notlike "$($Prefix)-*")
    {
        $Name = "$($Prefix)-$($Name)"
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
        $SettingsVars.Variables.Add($Name, @{ 'Value' = $Value ;
                                                'Description' = $Description ;
                                                'isEncrypted' = $isEncrypted })
    }
    
    Set-Content -Path $SettingsFilePath -Value (ConvertTo-JSON $SettingsVars) -Encoding UTF8
    Read-SmaJSONVariables $SettingsFilePath
}

Function Remove-LocalDevAutomationVariable
{
    Param(
        [Parameter(Mandatory=$False)] $SettingsFilePath,
        [Parameter(Mandatory=$True)]  $Name,
        [Parameter(Mandatory=$False)] $Prefix
        )
    if(-not $SettingsFilePath)
    {
        if(-not $Script:CurrentSettingsFile)
        {
            Throw-Exception -Type 'Variable File Not Set' `
                            -Message 'The variable file path has not been set'
        }
        $SettingsFilePath = $Script:CurrentSettingsFile
    }
    else
    {
        if($Script:CurrentSettingsFile -ne $SettingsFilePath)
        {
            Write-Warning -Message "Setting Default Variable file to [$SettingsFilePath]" `
                          -WarningAction 'Continue'
            $Script:CurrentSettingsFile = $SettingsFilePath
        }
    }

    if(Test-IsNullOrEmpty $Prefix)
    {
        if($SettingsFilePath -Match '.*\\(.+)\.json$')
        {
            $Prefix = $Matches[1]
        }
        else
        {
            Throw-Exception -Type 'UndeterminableDefaultPrefix' `
                            -Message 'Could not determine what the default prefix should be' `
                            -Property @{ 'SettingsFilePath' = $SettingsFilePath }
        }
    }

    if($Name -notlike "$($Prefix)-*")
    {
        $Name = "$($Prefix)-$($Name)"
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
                                     -Message 'The variable was not found in the current variable file. Try specifiying the file' `
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
        [string] $Name
    )

    Try
    {
        $Val = (Get-PasswordVaultCredential -UserName $Name -WithPassword)
        Write-Verbose -Message "Credential [$Name] found in PasswordVault"
    }
    Catch
    {
        $Val = Get-AutomationAsset -Type PSCredential -Name $Name
        if($Val) 
        {
            $SecurePassword = $Val.Password | ConvertTo-SecureString -asPlainText -Force
            $Credential = New-Object -TypeName System.Management.Automation.PSCredential($Val.Username, $SecurePassword)
        }
        else
        {
            Throw-Exception -Type 'CredentialNotFound' `
                            -Message 'Could not find credential' `
                            -Parameter @{ 'Name' = $Name }
        }

        $ExceptionInfo = Get-ExceptionInfo -Exception $_
        Switch -CaseSensitive ($ExceptionInfo.Type)
        {
            'CredentialNotFound'
            {
                Write-Verbose -Message "Storing [$Name] in Password Vault"
                Set-PasswordVaultCredential -UserName $Name -Resource "LocalDev:$([guid]::NewGuid())" -Password $Val.Password
            }
        }
    }
    $SecurePassword = $Val.Password | ConvertTo-SecureString -asPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential($Val.Username, $SecurePassword)
    $Credential
}

Function Set-LocalDevAutomationSchedule
{
    Param(
        [Parameter(Mandatory=$False)][String]    $SettingsFilePath,
        [Parameter(Mandatory=$True)] [String]    $Name,
        [Parameter(Mandatory=$False)][String]    $Prefix = [System.String]::Emptpy,
        [Parameter(Mandatory=$False)][String]    $Description = [System.String]::Emptpy,
        [Parameter(Mandatory=$False)]            $NextRun = $null,
        [Parameter(Mandatory=$False)]            $ExpirationTime = $null,
        [Parameter(Mandatory=$False)][Int]       $DayInterval = $null,
        [Parameter(Mandatory=$False)][String]    $RunbookName = [System.String]::Emptpy,
        [Parameter(Mandatory=$False)][HashTable] $Parameter = @{}
        )
    if(-not $SettingsFilePath)
    {
        if(-not $Script:CurrentSettingsFile)
        {
            Throw-Exception -Type 'Settings File Not Set' `
                            -Message 'The settings file path has not been set'
        }
        $SettingsFilePath = $Script:CurrentSettingsFile
    }
    else
    {
        if($Script:CurrentSettingsFile -ne $SettingsFilePath)
        {
            Write-Warning -Message "Setting Default Variable file to [$SettingsFilePath]" `
                          -WarningAction 'Continue'
            $Script:CurrentSettingsFile = $SettingsFilePath
        }
    }

    if(Test-IsNullOrEmpty $Prefix)
    {
        if($SettingsFilePath -Match '.*\\(.+)\.json$')
        {
            $Prefix = $Matches[1]
        }
        else
        {
            Throw-Exception -Type 'UndeterminableDefaultPrefix' `
                            -Message 'Could not determine what the default prefix should be' `
                            -Property @{ 'SettingsFilePath' = $SettingsFilePath }
        }
    }

    if($Name -notlike "$($Prefix)-*")
    {
        $Name = "$($Prefix)-$($Name)"
    }

    $SettingsVars = ConvertFrom-JSON -InputObject ((Get-Content -Path $SettingsFilePath) -as [String])
    if(Test-IsNullOrEmpty $SettingsVars.Schedules)
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
        Add-Member -InputObject $SettingsVars `
                   -MemberType NoteProperty `
                   -Value @{ $Name = @{'Description' = $Description ;
                                       'ExpirationTime' = $ExpirationTime -as [DateTime] ;
                                       'NextRun' = $NextRun -as [DateTime] ;
                                       'DayInterval' = $DayInterval ;
                                       'RunbookName' = $RunbookName ;
                                       'Parameter' = $(ConvertTo-JSON $Parameter) }} `
                   -Name Schedules `
                   -Force
    }
    else
    {
        if(($SettingsVars.Schedules | Get-Member -MemberType NoteProperty).Name -Contains $Name)
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
            Add-Member -InputObject $SettingsVars.Schedules `
                       -MemberType NoteProperty `
                       -Value @{'Description' = $Description ;
                                'ExpirationTime' = $ExpirationTime -as [DateTime] ;
                                'NextRun' = $NextRun -as [DateTime] ;
                                'DayInterval' = $DayInterval ;
                                'RunbookName' = $RunbookName ;
                                'Parameter' = $(ConvertTo-JSON $Parameter) } `
                       -Name $Name
        }
    }
    
    Set-Content -Path $SettingsFilePath -Value (ConvertTo-JSON $SettingsVars) -Encoding UTF8
}
Function Remove-LocalDevAutomationSchedule
{
    Param(
        [Parameter(Mandatory=$False)] $SettingsFilePath,
        [Parameter(Mandatory=$True)]  $Name,
        [Parameter(Mandatory=$False)] $Prefix
        )
    if(-not $SettingsFilePath)
    {
        if(-not $Script:CurrentSettingsFile)
        {
            Throw-Exception -Type 'Variable File Not Set' `
                            -Message 'The variable file path has not been set'
        }
        $SettingsFilePath = $Script:CurrentSettingsFile
    }
    else
    {
        if($Script:CurrentSettingsFile -ne $SettingsFilePath)
        {
            Write-Warning -Message "Setting Default Variable file to [$SettingsFilePath]" `
                          -WarningAction 'Continue'
            $Script:CurrentSettingsFile = $SettingsFilePath
        }
    }
    if(Test-IsNullOrEmpty $Prefix)
    {
        if($SettingsFilePath -Match '.*\\(.+)\.json$')
        {
            $Prefix = $Matches[1]
        }
        else
        {
            Throw-Exception -Type 'UndeterminableDefaultPrefix' `
                            -Message 'Could not determine what the default prefix should be' `
                            -Property @{ 'SettingsFilePath' = $SettingsFilePath }
        }
    }

    if($Name -notlike "$($Prefix)-*")
    {
        $Name = "$($Prefix)-$($Name)"
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