$Script:LocalSMAVariableLastUpdate = (Get-Date)
$Script:LocalSMAVariables = $null
$Script:CurrentVariableFile = $null
$env:LocalSMAVariableWarn = Select-FirstValid -Value $env:LocalSMAVariableWarn, $true -FilterScript { $_ -ne $null }

<#
.SYNOPSIS
    Returns a scriptblock that, when dot-sourced, will import a workflow and all its dependencies.

.DESCRIPTION
    Import-Workflow is a helper function to resolve dependencies of a given workflow. It must be
    invoked with a very specific syntax in order to import workflows into your current session.
    See the example.

    Import-Workflow only considers scripts whose full paths contain '\Dev\' in accordance with
    GMI convention. See Find-DeclaredCommand to modify this behavior if it is undesired.

.PARAMETER WorkflowName
    The name of the workflow to import.

.PARAMETER Path
    The path containing all ps1 files to search for workflow dependencies.

.EXAMPLE
    PS > . (Import-Workflow Test-Workflow)
#>
function Import-Workflow {
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
    $BaseWorkflowPath = $DeclaredCommands[$WorkflowName]
    $Stacked = @{$BaseWorkflowPath = $True}
    $TokenizeStack.Push($BaseWorkflowPath)
    $CompileStack.Push($BaseWorkflowPath)
    while ($TokenizeStack.Count -gt 0) {
        $ScriptPath = $TokenizeStack.Pop()
        $Tokens = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Path $ScriptPath), [ref] $null)
        $NeededCommands = ($Tokens | Where-Object -FilterScript { $_.Type -eq 'Command' }).Content
        foreach ($Command in $NeededCommands) {
            $NeededScriptPath = $DeclaredCommands[$Command]
            # If $NeededScriptPath is $null, we didn't find it when we searched declared
            # commands in the runbook path. We'll assume that is okay and that the command
            # is provided by some other means (e.g. a module import)
            if (($NeededScriptPath -ne $null) -and (-not $Stacked[$NeededScriptPath])) {
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
    Param( [Parameter(Mandatory=$True)]  [String] $Name )

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
        Throw-Exception -Type 'VariableDoesNotExist' -Message "Couldn't find variable $Name" -Property @{
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

    Write-Verbose -Message "Updating SMA variables in memory"
    $Script:LocalSMAVariableLastUpdate = Get-Date
    $FilesToProcess = (Get-ChildItem -Path $env:SMARunbookPath -Include '*.json' -Recurse).FullName
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
    $TypeMap = @{
        'String'  = [String];
        'Str'     = [String];
        'Integer' = [Int];
        'Int'     = [Int]
    }

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
                $VarType = Select-FirstValid -Value @($TypeMap[$Var.Type], $([String]))
                $retVar = New-Object -TypeName 'PSObject' -Property @{ 'Name' = $VariableName; 'Value' = ($var.Value -As $VarType)}
                $Script:LocalSMAVariables[$VariableName] = $retVar
            }
        }
    }
}

Function Set-LocalDevAutomationVariable
{
    Param(
        [Parameter(Mandatory=$False)] $VariableFilePath,
        [Parameter(Mandatory=$True)]  $Name,
        [Parameter(Mandatory=$True)]  $Value,
        [Parameter(Mandatory=$False)] $Description = [System.String]::Empty,
        [Parameter(Mandatory=$False)] $isEncrypted = $False,
        [Parameter(Mandatory=$False)] $Type = 'String'
        )
    if(-not $VariableFilePath)
    {
        if(-not $Script:CurrentVariableFile)
        {
            Throw-Exception -Type 'Variable File Not Set' `
                            -Message 'The variable file path has not been set'
        }
        $VariableFilePath = $Script:CurrentVariableFile
    }
    else
    {
        if($Script:CurrentVariableFile -ne $VariableFilePath)
        {
            Write-Warning -Message "Setting Default Variable file to [$VariableFilePath]" `
                          -WarningAction 'Continue'
            $Script:CurrentVariableFile = $VariableFilePath
        }
    }

    $VariableJSON = ConvertFrom-JSON -InputObject ((Get-Content -Path $VariableFilePath) -as [String])
    if(Test-IsNullOrEmpty $VariableJSON.Variables)
    {
        Add-Member -InputObject $VariableJSON -MemberType NoteProperty -Value @() -Name Variables
    }
    if(($VariableJSON.Variables | Get-Member -MemberType NoteProperty).Name -Contains $Name)
    {
        $VariableJSON.Variables."$Name".Value = $Value
        if($Description) { $VariableJSON.Variables."$Name".Description = $Description }
        if($Encrypted)   { $VariableJSON.Variables."$Name".Encrypted   = $Encrypted   }
    }
    else
    {
        Add-Member -InputObject $VariableJSON.Variables `
                   -MemberType NoteProperty `
                   -Value @{'Value' = $Value ;
                            'Description' = $Description ;
                            'isEncrypted' = $isEncrypted ;
                            'Type' = $Type } `
                            -Name $Name
    }
    
    Set-Content -Path $VariableFilePath -Value (ConvertTo-JSON $VariableJSON)
    Read-SmaJSONVariables $VariableFilePath
}

Function Remove-LocalDevAutomationVariable
{
    Param(
        [Parameter(Mandatory=$False)] $VariableFilePath,
        [Parameter(Mandatory=$True)]  $Name
        )
    if(-not $VariableFilePath)
    {
        if(-not $Script:CurrentVariableFile)
        {
            Theow-Exception -Type 'Variable File Not Set' `
                            -Message 'The variable file path has not been set'
        }
        $VariableFilePath = $Script:CurrentVariableFile
    }
    else
    {
        if($Script:CurrentVariableFile -ne $VariableFilePath)
        {
            Write-Warning -Message "Setting Default Variable file to [$VariableFilePath]" `
                          -WarningAction 'Continue'
            $Script:CurrentVariableFile = $VariableFilePath
        }
    }

    $VariableJSON = ConvertFrom-JSON -InputObject ((Get-Content -Path $VariableFilePath) -as [String])
    if(Test-IsNullOrEmpty $VariableJSON.Variables)
    {
        Add-Member -InputObject $VariableJSON -MemberType NoteProperty -Value @() -Name Variables
    }
    if(($VariableJSON.Variables | Get-Member -MemberType NoteProperty).Name -Contains $Name)
    {
        $VariableJSON.Variables = $VariableJSON.Variables | Select-Object -Property * -ExcludeProperty $Name
        Set-Content -Path $VariableFilePath -Value (ConvertTo-JSON $VariableJSON)
        Read-SmaJSONVariables $VariableFilePath
    }
    else
    {
        Write-Warning (New-Exception -Type 'Variable Not found' `
                                     -Message "The variable was not found in the current variable file. Try specifiying the file" `
                                     -Property @{ 'VariableName' = $Name ;
                                                  'CurrentFilePath' = $VariableFilePath ;
                                                  'VariableJSON' = $VariableJSON }) `
                      -WarningAction 'Continue'
    }
}

#region Code from EmulatedAutomationActivities
Workflow Get-AutomationPSCredential {
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name
    )

    $Val = Get-AutomationAsset -Type PSCredential -Name $Name

    if($Val) {
        $SecurePassword = $Val.Password | ConvertTo-SecureString -asPlainText -Force
        $Cred = New-Object -TypeName System.Management.Automation.PSCredential($Val.Username, $SecurePassword)

        $Cred
    }
}
#endregion

<#
.SYNOPSIS
    Gets one or credentials using Get-AutomationPSCredential.

.DESCRIPTION
    Get-BatchAutomationPSCredential takes a hashtable which maps a friendly name to
    a credential name. Each credential in the hashtable will be retrieved using
    Get-AutomationPSCredential, will be accessible by its friendly name via the
    returned object.

.PARAMETER Alias
    A hashtable mapping credential friendly names to a name passed to Get-AutomationPSCredential.

.EXAMPLE
    PS > $Creds = Get-BatchAutomationPSCredential -Alias @{'TestCred' = 'GENMILLS\M3IS052'; 'TestCred2' = 'GENMILLS\M2IS254'}

    PS > $Creds.TestCred


    PSComputerName        : localhost
    PSSourceJobInstanceId : e2d9e9dc-2740-49ef-87d6-34e3334324e4
    UserName              : GENMILLS\M3IS052
    Password              : System.Security.SecureString

    PS > $Creds.TestCred2


    PSComputerName        : localhost
    PSSourceJobInstanceId : 383da6c1-03f7-4b74-afc6-30e901972a5e
    UserName              : GENMILLS.com\M2IS254
    Password              : System.Security.SecureString
#>
Workflow Get-BatchAutomationPSCredential
{
    param(
        [Parameter(Mandatory=$True)] [Hashtable] $Alias
    )

    $Creds = New-Object -TypeName 'PSObject'
    foreach($Key in $Alias.Keys)
    {
        $Cred = Get-AutomationPSCredential -Name $Alias[$Key]
        Add-Member -InputObject $Creds -Name $Key -Value $Cred -MemberType NoteProperty
        Write-Verbose -Message "Credential [$($Key)] = [$($Alias[$Key])]"
    }
    return $Creds
}
Export-ModuleMember -Function * -Verbose:$false