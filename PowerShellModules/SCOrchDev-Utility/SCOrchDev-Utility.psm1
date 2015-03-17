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
          [Parameter(Position=1, Mandatory=$False)] [string[]] $Property=@('*'))
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
        [Parameter(Mandatory=$True)]
        [String]
        $Path
    )
    $RunbookPaths = Get-ChildItem -Path $Path -Include '*.ps1' -Recurse

    $DeclaredCommandMap = @{}
    foreach ($Path in $RunbookPaths) 
    {
        $Tokens = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Path $Path), [ref] $null)
        For($i = 0 ; $i -lt $Tokens.Count - 1 ; $i++)
        {
            $Token = $Tokens[$i]
            if($Token.Type -eq 'Keyword' -and $Token.Content -in @('function','workflow'))
            {
                Write-Debug -Message "Found command $($NextToken.Content) in $Path of type $($Token.Content)"
                $NextToken = $Tokens[$i+1]
                $DeclaredCommandMap."$($NextToken.Content)" = @{ 'Path' = $Path ; 'Type' = $Token.Content}
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
        Write-Verbose -Message 'Starting [New-ZipFile]'
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
    Param([Parameter(Mandatory=$false) ][string] $SourceDir = 'C:\')
    
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
    Param ( 
            [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName = $True)] 
            [string]$Path 
          )
 
    [byte[]]$byte = get-content -Encoding byte -ReadCount 4 -TotalCount 4 -Path $Path
    if ( $byte[0] -eq 0xef -and $byte[1] -eq 0xbb -and $byte[2] -eq 0xbf )
    { 
        Write-Output 'UTF8' 
    }
    elseif ($byte[0] -eq 0xfe -and $byte[1] -eq 0xff)
    { 
        Write-Output 'Unicode' 
    }
    elseif ($byte[0] -eq 0 -and $byte[1] -eq 0 -and $byte[2] -eq 0xfe -and $byte[3] -eq 0xff)
    { 
        Write-Output 'UTF32' 
    }
    elseif ($byte[0] -eq 0x2b -and $byte[1] -eq 0x2f -and $byte[2] -eq 0x76)
    { 
        Write-Output 'UTF7'
    }
    else
    { 
        Write-Output 'ASCII' 
    }
}
<#
    .Synopsis
#>
Function ConvertTo-UTF8
{
    Param ( 
            [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName = $True)] 
            [string]$Path 
          )
    $File = Get-Item $Path
    $content = Get-Content $Path
    if ( $content -ne $null ) 
    {
        Remove-Item -Path $file.FullName -Force
        $content | Out-File -FilePath $file.FullName -Encoding utf8
    } 
    else
    {
        Throw-Exception -Type 'NoContentFound' `
                        -Message 'Could not read the file' `
                        -Property @{ 'Path' = $Path ;
                                     'File' = $(ConvertTo-JSON $File) ;
                                     'Content' = $content }
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
    Param([Parameter(Mandatory=$True)] $Path)
    
    $CurrentPSModulePath = [System.Environment]::GetEnvironmentVariable('PSModulePath')
    if($CurrentPSModulePath.ToLower().Contains($Path.ToLower()))
    {
        Write-Verbose "The path [$Path] was not in the environment path [$CurrentPSModulePath]. Adding."
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
          
    .EXAMPLE
        Enable-RemotePsRemoting -ComputerName <Computer> -Credential <Credential>


#>
Function Enable-RemotePsRemoting
{
    param( [Parameter(Mandatory=$True)][String] $Computername,
           [Parameter(Mandatory=$True)][PSCredential]$Credential )

    Set-StrictMode -Version Latest
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    $username = $credential.Username
    $password = $credential.GetNetworkCredential().Password
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

    Write-Verbose "Configuring $computername"
    $command = "powershell -NoProfile -EncodedCommand $encoded"
    $null = Invoke-WmiMethod -Computer $computername -Credential $credential `
    Win32_Process Create -Args $command
    Write-Verbose 'Testing connection'

    $attempts = 0
    do
    {
        try 
        {
            $output = Invoke-Command $computername { Get-WmiObject Win32_ComputerSystem } -Credential $credential
            $status = 'Success'
        }
        catch
        {
            if($attempts -ge 10)
            {
                Throw-Exception -Type 'FailedToConfigurePSRemoting' `
                                -Message 'Failed to configure PS remoting on the target box' `
                                -Property @{ 'ComputerName' = $Computername ;
                                             'Credential' = $Credential.UserName ;
                                             'ErrorMessage' = Convert-ExceptionToString -Exception $_ }
            }
            else
            {
                Write-Verbose -Message 'Not yet configured'
                $attempts = $attempts + 1
                Start-Sleep -Seconds 5
            }
            $status = 'Failure'
        }
    } while($status -ne 'Success')
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
    Param([Parameter(Mandatory=$True)] $FileItemPath)
    
    $ContainerPath = $FileItemPath -replace '[^\\]+$',''
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
        [Parameter(Mandatory=$False)]
        [String] 
        $ComputerName,

        [Parameter(Mandatory=$False)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory=$False)]
        [ValidateSet('Basic','Credssp', 'Default', 'Digest', 'Kerberos', 'Negotiate', 'NegotiateWithImplicitCredential')]
        [String]
        $Authentication = 'CredSSP'
    )

    $InvokeCommandParameters = @{}
    if(-not (Test-IsNullOrEmpty -String $ComputerName))
    {
        $InvokeCommandParameters['ComputerName'] = $ComputerName
    }
    if($Credential -ne $null)
    {
        $InvokeCommandParameters['Credential'] = $Credential
        $InvokeCommandParameters['Authentication'] = $Authentication
        # If a credential is provided, we must specify a computer name.
        if($InvokeCommandParameters['ComputerName'] -eq $null)
        {
            $InvokeCommandParameters['ComputerName'] = Get-RemotingComputer
        }
    }
    return $InvokeCommandParameters
}

Export-ModuleMember -Function * -Verbose:$false -Debug:$false
# SIG # Begin signature block
# MIIOfQYJKoZIhvcNAQcCoIIObjCCDmoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUimpqUjAqrZSU/BnVjKu2AGeQ
# 9+SgggqQMIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# CisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBRjSGBB
# reO2Cp4t3u9qNlRUaxdj1TANBgkqhkiG9w0BAQEFAASBgFvLhW73VE1uNu0TItdl
# T4Ory+/t29ak+HsxOQkJpaHI7wIvUNgElUVcvC8J2vAmH6GIrDnFkZBxHuCq/ttm
# Y4f2lfiX7f+SXASLnvY7jp5Cr19lTkBKzYqGabE1HJvhPhR5U+9jM7qdTS11M7t3
# SnZYKjNJZWt62ivs+aQ2eJKpoYICCzCCAgcGCSqGSIb3DQEJBjGCAfgwggH0AgEB
# MHIwXjELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9u
# MTAwLgYDVQQDEydTeW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0g
# RzICEA7P9DjI/r81bgTYapgbGlAwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJAzEL
# BgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1MDMxNzIyMzU0OFowIwYJKoZI
# hvcNAQkEMRYEFHN49JZCEvYjx1apuq3b2AwPgXI5MA0GCSqGSIb3DQEBAQUABIIB
# AAWY1sRJZlWApJQvuMQqdS3R8SU9MxbNXuTwCxio+3NtVqqnYsRJH6jo0CgqZRwD
# vGKZk5MbC2WTVk307CcbmVbMlflBRtL4vq2JfTFcV6pdVdMxV30K9voi1KtiRi4H
# r9Q0CcDrlJdJVmjAGuhm7FoPKWUhbAk7VL1UtN0xDQ6G3c7HQozzbvXaIqm4AkVu
# dv4pttD6wx6zpcJ9L/2hwZXQs90zixjG5+a2yQsvpRSORVeVItUcrwxLzB2w376K
# a9VLbHNc8g6ErAkXesc2h/4uQ2icihzgaFJdlMxCJeFtwGRGcB/y8zzH1vkcQaE8
# OAxiULVLM/z6USzLRDrPWUE=
# SIG # End signature block
