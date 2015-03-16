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

    Write-Verbose -Message 'Updating SMA variables in memory'
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
    
    Set-Content -Path $SettingsFilePath -Value (ConvertTo-JSON $SettingsVars)
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
        Set-Content -Path $SettingsFilePath -Value (ConvertTo-JSON $SettingsVars)
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
        Add-Member -InputObject $Creds -Name $Key -Value $Cred -MemberType NoteProperty -Force
        Write-Verbose -Message "Credential [$($Key)] = [$($Alias[$Key])]"
    }
    return $Creds
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
    
    Set-Content -Path $SettingsFilePath -Value (ConvertTo-JSON $SettingsVars)
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
        Set-Content -Path $SettingsFilePath -Value (ConvertTo-JSON $SettingsVars)
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
# SIG # Begin signature block
# MIIOfQYJKoZIhvcNAQcCoIIObjCCDmoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUn0mLs+r5f54E81o0bCmVqXfK
# Q16gggqQMIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# CisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBR17VMF
# C7SvI3PFO2z8NBjvLL/NdDANBgkqhkiG9w0BAQEFAASBgH/lhxYnCVfrrXahVxYO
# 2kz7lgt2B5SYCdA/exkLJVQe2POKja5luieo3YQy+67Hpzn7RjdOT/lNNYlTF2Ga
# 8desiVafl4HTnU5jv0CjC6OxxjTPF7Gyh6lAN+Zf1rma3v0y/hPJ+KSCKmMsz9nT
# 96x1MqU1p9an5s+9pFsA+zCcoYICCzCCAgcGCSqGSIb3DQEJBjGCAfgwggH0AgEB
# MHIwXjELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9u
# MTAwLgYDVQQDEydTeW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0g
# RzICEA7P9DjI/r81bgTYapgbGlAwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJAzEL
# BgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1MDMxNjIwMTQzN1owIwYJKoZI
# hvcNAQkEMRYEFB4Xg8w/2WDUF6Us6NNemuAJc1rbMA0GCSqGSIb3DQEBAQUABIIB
# ACrHejZ3NsRbOA2wU7ewauwMdHY9PWhgloKtqOlJxFmD+coDs9gIrsCxd+dL1mIA
# tqmEGZHgGhuht3bIXOjDVAC4U0h8u16rq7K3tnw0ku5ti2hhAgN3Z8Gus2e9Kr3v
# O6muLEBT/gWjwb/RzUDsJ41mTyj1Zu0PKbpnEoRrEppQ0EMdTcG7v0ME9GPsEO3Y
# B6R0FY0ZSWX68GcU4Ceju4Y/8zPpsOe4nrS33vdsNAMI1oT/jAGts4c2hsYu6usy
# OXxB5q59lgMkfMeUt0MIVhvuGhDJYU9cMFmJ+qi7/4MTDOIvPckWPe391AdqedgQ
# ieBqDqM9/ebVEZtXDlcdbBM=
# SIG # End signature block
