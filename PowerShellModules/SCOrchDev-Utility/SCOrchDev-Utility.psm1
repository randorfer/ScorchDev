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
        $KeyName = Invoke-Command $KeyFilterScript -ArgumentList $KeyName
        if(-not (Test-IsNullOrEmpty $KeyName))
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
        $Key = Invoke-Command $KeyFilterScript -ArgumentList $Key
        if(-not (Test-IsNullOrEmpty $Key))
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
    Param(
        [Parameter(Mandatory = $True)]
        [string]
        $SourceDir,

        [Parameter(Mandatory = $True)]
        [string]
        $ZipFilePath,
    
        [Parameter(Mandatory = $False)]
        [bool]
        $OverwriteExisting = $True
    )
            
    $Null = $(
        Write-Verbose -Message 'Starting [New-ZipFile]'
        Write-Verbose -Message "`$SourceDir [$SourceDir]"
        Write-Verbose -Message "`$ZipFilePath [$ZipFilePath]"
                
        if($OverwriteExisting)
        {
            if(Test-Path -Path $ZipFilePath)
            {
                Remove-Item $ZipFilePath -Force -Confirm:$False
            }
        }

        if(-not (Test-Path -Path "$($ZipFilePath.Substring(0,$ZipFilePath.LastIndexOf('\')))"))
        {
            $newDir = New-Item -ItemType Directory `
                               -Path "$($ZipFilePath.Substring(0,$ZipFilePath.LastIndexOf('\')))" `
                               -Force `
                               -Confirm:$False
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $CompressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
        [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceDir, $ZipFilePath, $CompressionLevel, $False)
        Write-Verbose -Message 'Finished [New-ZipFile]'
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
    [OutputType([System.IO.DirectoryInfo])]
    Param(
        [Parameter(Mandatory = $False, ValueFromPipeline = $True)]
        [string]
        $SourceDir = 'C:\'
    )
    
    do
    {
        $TempDirectory   = "$($SourceDir)\$([System.Guid]::NewGuid())"
        $DirectoryExists = Test-Path -Path $TempDirectory
    }
    while($DirectoryExists)

    New-Item -ItemType Directory $TempDirectory
}

<#
.SYNOPSIS
    Gets file encoding. From http://poshcode.org/2059
    
.DESCRIPTION
    The Get-FileEncoding function determines encoding by looking at Byte Order Mark (BOM).
    Based on port of C# code from http://www.west-wind.com/Weblog/posts/197245.aspx
    
.EXAMPLE
    Get-ChildItem  *.ps1 | select FullName, @{n='Encoding';e={Get-FileEncoding $_.FullName}} | where {$_.Encoding -ne 'ASCII'}
    This command gets ps1 files in current directory where encoding is not ASCII

.EXAMPLE
    Get-ChildItem  *.ps1 | select FullName, @{n='Encoding';e={Get-FileEncoding $_.FullName}} | where {$_.Encoding -ne 'ASCII'} | foreach {(get-content $_.FullName) | set-content $_.FullName -Encoding ASCII}
    Same as previous example but fixes encoding using set-content
#>
Function Get-FileEncoding
{
    [OutputType([string])]
    Param ( 
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)] 
        [string]$Path 
    )
 
    [byte[]]$byte = Get-Content -Encoding byte -ReadCount 4 -TotalCount 4 -Path $Path
    if ( $byte[0] -eq 0xef -and $byte[1] -eq 0xbb -and $byte[2] -eq 0xbf )
    {
        Return 'UTF8'
    }
    elseif ($byte[0] -eq 0xfe -and $byte[1] -eq 0xff)
    {
        Return 'Unicode'
    }
    elseif ($byte[0] -eq 0 -and $byte[1] -eq 0 -and $byte[2] -eq 0xfe -and $byte[3] -eq 0xff)
    {
        Return 'UTF32'
    }
    elseif ($byte[0] -eq 0x2b -and $byte[1] -eq 0x2f -and $byte[2] -eq 0x76)
    {
        Return 'UTF7'
    }
    Return 'ASCII'
}
<#
.Synopsis
    Converts a filt to UTF8

.Parameter Path
    The path to the file to convert
#>
Function ConvertTo-UTF8
{
    Param ( 
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)] 
        [string]$Path 
    )
    $File = Get-Item $Path
    $content = Get-Content $Path
    if ( $content -ne $Null ) 
    {
        Remove-Item -Path $File.FullName -Force
        $content | Out-File -FilePath $File.FullName -Encoding utf8
    } 
    else
    {
        Throw-Exception -Type 'NoContentFound' `
        -Message 'Could not read the file' `
        -Property @{
            'Path'  = $Path
            'File'  = $(ConvertTo-Json -InputObject $File)
            'Content' = $content
        }
    }
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
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        $Path
    )
    
    $CurrentPSModulePath = [System.Environment]::GetEnvironmentVariable('PSModulePath')
    if($CurrentPSModulePath.ToLower().Contains($Path.ToLower()))
    {
        Write-Verbose -Message "The path [$Path] was not in the environment path [$CurrentPSModulePath]. Adding."
        [Environment]::SetEnvironmentVariable( 'PSModulePath', "$CurrentPSModulePath;$Path", [System.EnvironmentVariableTarget]::Machine )
    }
}
<#
.SYNOPSIS
    Enables PowerShell Remoting on a remote computer. Requires that the machine
    responds to WMI requests, and that its operating system is Windows Vista or
    later.

    Adapted from http://www.davidaiken.com/2011/01/12/enable-powershell-remoting-on-windows-azure/
    From Windows PowerShell Cookbook (O'Reilly)
    by Lee Holmes (http://www.leeholmes.com/guide)

.Parameter Computername
    The name of the computer to enable PSRemoting on

.Parameter Credential
    The Credential to use when connecting to the remote computer
          
.EXAMPLE
    Enable-RemotePsRemoting -ComputerName <Computer> -Credential <Credential>
#>
Function Enable-RemotePsRemoting
{
    Param(
        [Parameter(Mandatory = $True)]
        [String]
        $Computername,
    
        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential
    )

    Set-StrictMode -Version Latest
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    $username = $Credential.Username
    $password = $Credential.GetNetworkCredential().Password
    $script = @"
`$log = Join-Path `$env:TEMP Enable-RemotePsRemoting.output.txt
Remove-Item -Force `$log -ErrorAction SilentlyContinue
Start-Transcript -Path `$log

## Create a task that will run with full network privileges.
## In this task, we call Enable-PsRemoting

schtasks /CREATE /TN 'Enable Remoting' /SC WEEKLY /RL HIGHEST ``
         /RU $username /RP $password ``
         /TR "powershell -noprofile -command Enable-PsRemoting -Force" /F |
         Out-String

schtasks /RUN /TN 'Enable Remoting' | Out-String
`$securePass = ConvertTo-SecureString $password -AsPlainText -Force
`$credential = New-Object Management.Automation.PsCredential $username,`$securepass

## Wait for the remoting changes to come into effect
for(`$count = 1; `$count -le 10; `$count++)
{
    `$output = Invoke-Command localhost { 1 } -Cred `$credential ``
                              -ErrorAction SilentlyContinue
    if(`$output -eq 1) { break; }

    "Attempt `$count : Not ready yet."
    Sleep 5
}

## Delete the temporary task
schtasks /DELETE /TN 'Enable Remoting' /F | Out-String
Stop-Transcript
"@

    $commandBytes = [System.Text.Encoding]::Unicode.GetBytes($script)
    $encoded = [Convert]::ToBase64String($commandBytes)

    Write-Verbose -Message "Configuring $Computername"
    $command = "powershell -NoProfile -EncodedCommand $encoded"
    $Null = Invoke-WmiMethod -ComputerName $Computername -Credential $Credential `
    Win32_Process Create -Args $command
    Write-Verbose -Message 'Testing connection'

    $attempts = 0
    do
    {
        try 
        {
            $output = Invoke-Command $Computername {
                Get-WmiObject -Class Win32_ComputerSystem 
            } -Credential $Credential
            $status = 'Success'
        }
        catch
        {
            if($attempts -ge 10)
            {
                Throw-Exception -Type 'FailedToConfigurePSRemoting' `
                                -Message 'Failed to configure PS remoting on the target box' `
                                -Property @{
                    'ComputerName' = $Computername
                    'Credential' = $Credential.UserName
                    'ErrorMessage' = Convert-ExceptionToString -Exception $_
                }
            }
            else
            {
                Write-Verbose -Message 'Not yet configured'
                $attempts = $attempts + 1
                Start-Sleep -Seconds 5
            }
            $status = 'Failure'
        }
    }
    while($status -ne 'Success')
    Write-Verbose -Message 'Success'
}
<#
.Synopsis
    Takes a passed item path and creates the container if it does not already exist
    
.Parameter FileItemPath
    The path to the file who's container object will be created if it does not already exist
#>
Function New-FileItemContainer
{
    Param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        $FileItemPath
    )
    
    $ContainerPath = $FileItemPath -replace '[^\\]+$', ''
    if(-Not (Test-Path -Path $ContainerPath))
    {
        Write-Verbose -Message 'Creating Directory'
        New-Item -ItemType Directory $ContainerPath
    }
    else
    {
        Write-Verbose -Message 'Directory Existed'
        Get-Item $ContainerPath
    }
}
<#
.SYNOPSIS
    Returns a hashtable containing parameters to be passed it Invoke-Command if you
    want to optionally perform remoting.

.DESCRIPTION
    Returns parameters suitable for passing to Invoke-Command that will optionally
    perform PowerShell remoting.

    If $ComputerName and $Credential are $null, no remoting will be performed. If
    only $ComputerName is $null, Get-RemotingComputer will be be called to retrieve
    an acceptable computer to use for "local" remoting.

.PARAMETER ComputerName
    The name of the computer to remote to.

.PARAMETER Credential
    The credential to use for remoting.

.PARAMETER Authentication
    The authentication mechanism to use with the credential.
#>
Function Get-OptionalRemotingParameter
{
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $False)]
        [String] 
        $Computername,

        [Parameter(Mandatory = $False)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $False)]
        [ValidateSet('Basic','Credssp', 'Default', 'Digest', 'Kerberos', 'Negotiate', 'NegotiateWithImplicitCredential')]
        [String]
        $Authentication = 'CredSSP'
    )

    $InvokeCommandParameters = @{}
    if(-not (Test-IsNullOrEmpty -String $Computername))
    {
        $InvokeCommandParameters['ComputerName'] = $Computername
    }
    if($Credential -ne $Null)
    {
        $InvokeCommandParameters['Credential'] = $Credential
        $InvokeCommandParameters['Authentication'] = $Authentication
        # If a credential is provided, we must specify a computer name.
        if($InvokeCommandParameters['ComputerName'] -eq $Null)
        {
            $InvokeCommandParameters['ComputerName'] = Get-RemotingComputer
        }
    }
    return $InvokeCommandParameters
}

Export-ModuleMember -Function * -Verbose:$False -Debug:$False
# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU82SvajrGwqDp2ibyDlt+UO8m
# nnigggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
# AQUFADAUMRIwEAYDVQQDDAlTQ09yY2hEZXYwHhcNMTUwMzA5MTQxOTIxWhcNMTkw
# MzA5MDAwMDAwWjAUMRIwEAYDVQQDDAlTQ09yY2hEZXYwgZ8wDQYJKoZIhvcNAQEB
# BQADgY0AMIGJAoGBANbZ1OGvnyPKFcCw7nDfRgAxgMXt4YPxpX/3rNVR9++v9rAi
# pY8Btj4pW9uavnDgHdBckD6HBmFCLA90TefpKYWarmlwHHMZsNKiCqiNvazhBm6T
# XyB9oyPVXLDSdid4Bcp9Z6fZIjqyHpDV2vas11hMdURzyMJZj+ibqBWc3dAZAgMB
# AAGjRjBEMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBQ75WLz6WgzJ8GD
# ty2pMj8+MRAFTTAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQEFBQADgYEAoK7K
# SmNLQ++VkzdvS8Vp5JcpUi0GsfEX2AGWZ/NTxnMpyYmwEkzxAveH1jVHgk7zqglS
# OfwX2eiu0gvxz3mz9Vh55XuVJbODMfxYXuwjMjBV89jL0vE/YgbRAcU05HaWQu2z
# nkvaq1yD5SJIRBooP7KkC/zCfCWRTnXKWVTw7hwxggFIMIIBRAIBATAoMBQxEjAQ
# BgNVBAMMCVNDT3JjaERldgIQEdV66iePd65C1wmJ28XdGTAJBgUrDgMCGgUAoHgw
# GAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGC
# NwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQx
# FgQUTD1tIsNppTermZzBuXoE32F1peQwDQYJKoZIhvcNAQEBBQAEgYDGzMDK88Rr
# UwhsNtYAffjqqj15ATvI3ag7tc7x5dVosRn6KNASHVEv45AfLbxFxMCPrH4XS1ud
# p1t3kMB9f492C1KpVoPe1cgzFeZUUp/91kJaQPmzygplk6gwv1nLatW59Jpu5brg
# Xrs7axROJhYeta1tkJcCo3QGKWkMRIVJSQ==
# SIG # End signature block
