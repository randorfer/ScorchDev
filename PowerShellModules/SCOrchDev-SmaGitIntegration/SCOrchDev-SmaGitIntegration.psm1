<#
    .Synopsis
        Looks for the tag workflow in a file and returns the next string
    
    .Parameter FilePath
        The path to the file to search
#>
Function Get-SmaWorkflowNameFromFile
{
    Param([Parameter(Mandatory=$true)][string] $FilePath)

    $FileContent = Get-Content $FilePath
    if("$FileContent" -match '(?im)workflow\s+([^\s]+)')
    {
        return $Matches[1]
    }
    else
    {
        Throw-Exception -Type 'WorkflowNameNotFound' `
                        -Message 'Could not find the workflow tag and corresponding workflow name' `
                        -Property @{ 'FileContent' = "$FileContent" }
    }
}
<#
    .Synopsis
        Tags a current tag line and compares it to the passed
        commit and repository. If the commit is not the same
        update the tag line and return new version
    
    .Parameter TagLine
        The current tag string from an SMA runbook

    .Parameter CurrentCommit
        The current commit string

    .Parameter RepositoryName
        The name of the repository that is being processed
#>
Function New-SmaChangesetTagLine
{
    Param([Parameter(Mandatory=$false)][string] $TagLine,
          [Parameter(Mandatory=$true)][string]  $CurrentCommit,
          [Parameter(Mandatory=$true)][string]  $RepositoryName)

    $NewVersion = $False
    if($TagLine -match 'CurrentCommit:([^;]+);')
    {
        if($Matches[1] -ne $CurrentCommit)
        {
            $NewVersion = $True
            $TagLine = $TagLine.Replace($Matches[1],$CurrentCommit) 
        }
    }
    else
    {
        Write-Verbose -Message "[$TagLine] Did not have a current commit tag."
        $TagLine = "CurrentCommit:$($CurrentCommit);$($TagLine)"
        $NewVersion = $True
    }
    if($TagLine -match 'RepositoryName:([^;]+);')
    {
        if($Matches[1] -ne $RepositoryName)
        {
            $NewVersion = $True
            $TagLine = $TagLine.Replace($Matches[1],$RepositoryName) 
        }
    }
    else
    {
        Write-Verbose -Message "[$TagLine] Did not have a RepositoryName tag."
        $TagLine = "RepositoryName:$($RepositoryName);$($TagLine)"
        $NewVersion = $True
    }
    return (ConvertTo-JSON -InputObject @{'TagLine' = $TagLine ;
                                          'NewVersion' = $NewVersion } `
                           -Compress)
}
<#
    .Synopsis
        Returns all variables in a JSON settings file

    .Parameter FilePath
        The path to the JSON file containing SMA settings
#>
Function Get-SmaGlobalFromFile
{
    Param([Parameter(Mandatory=$false)]
          [string] 
          $FilePath,
          
          [ValidateSet('Variables','Schedules')]
          [Parameter(Mandatory=$false)]
          [string] 
          $GlobalType )

    $ReturnInformation = @{}
    try
    {
        $SettingsJSON = (Get-Content $FilePath) -as [string]
        $SettingsObject = ConvertFrom-Json -InputObject $SettingsJSON
        $SettingsHashTable = ConvertFrom-PSCustomObject $SettingsObject
        
        if(-not ($SettingsHashTable.ContainsKey($GlobalType)))
        {
            Throw-Exception -Type 'GlobalTypeNotFound' `
                            -Message 'Global Type not found in settings file.' `
                            -Property @{ 'FilePath' = $FilePath ;
                                         'GlobalType' = $GlobalType ;
                                         'SettingsJSON' = $SettingsJSON }
        }

        $GlobalTypeObject = $SettingsHashTable."$GlobalType"
        $GlobalTypeHashTable = ConvertFrom-PSCustomObject $GlobalTypeObject -ErrorAction SilentlyContinue

        if(-not $GlobalTypeHashTable)
        {
            Throw-Exception -Type 'SettingsNotFound' `
                            -Message 'Settings of specified type not found in file' `
                            -Property @{ 'FilePath' = $FilePath ;
                                         'GlobalType' = $GlobalType ;
                                         'SettingsJSON' = $SettingsJSON }
        }

        foreach($Key in $GlobalTypeHashTable.Keys)
        {
            $ReturnInformation.Add($key, $GlobalTypeHashTable."$Key") | Out-Null
        }
                
    }
    catch
    {
        Write-Exception -Exception $_ -Stream Warning
    }

    return (ConvertTo-JSON $ReturnInformation -Compress)
}
<#
    .Synopsis
        Updates a Global RepositoryInformation string with the new commit version
        for the target repository

    .Parameter RepositoryInformation
        The JSON representation of a repository

    .Parameter RepositoryName
        The name of the repository to update

    .Paramter Commit
        The new commit to store
#>
Function Set-SmaRepositoryInformationCommitVersion
{
    Param([Parameter(Mandatory=$false)][string] $RepositoryInformation,
          [Parameter(Mandatory=$false)][string] $RepositoryName,
          [Parameter(Mandatory=$false)][string] $Commit)
    
    $_RepositoryInformation = (ConvertFrom-JSON $RepositoryInformation)
    $_RepositoryInformation."$RepositoryName".CurrentCommit = $Commit

    return (ConvertTo-Json $_RepositoryInformation -Compress)
}
Function Get-GitRepositoryWorkflowName
{
    Param([Parameter(Mandatory=$false)][string] $Path)

    $RunbookNames = @()
    $RunbookFiles = Get-ChildItem -Path $Path `
                                  -Filter '*.ps1' `
                                  -Recurse `
                                  -File
    foreach($RunbookFile in $RunbookFiles)
    {
        $RunbookNames += Get-SmaWorkflowNameFromFile -FilePath $RunbookFile.FullName
    }
    $RunbookNames
}
Function Get-GitRepositoryVariableName
{
    Param([Parameter(Mandatory=$false)][string] $Path)

    $RunbookNames = @()
    $RunbookFiles = Get-ChildItem -Path $Path `
                                  -Filter '*.json' `
                                  -Recurse `
                                  -File
    foreach($RunbookFile in $RunbookFiles)
    {
        $RunbookNames += Get-SmaWorkflowNameFromFile -FilePath $RunbookFile.FullName
    }
    Return $RunbookNames
}
Function Get-GitRepositoryAssetName
{
    Param([Parameter(Mandatory=$false)][string] $Path)

    $Assets = @{ 'Variable' = @() ;
                 'Schedule' = @() }
    $AssetFiles = Get-ChildItem -Path $Path `
                                  -Filter '*.json' `
                                  -Recurse `
                                  -File
    
    foreach($AssetFile in $AssetFiles)
    {
        $VariableJSON = Get-SmaGlobalFromFile -FilePath $AssetFile.FullName -GlobalType Variables
        $ScheduleJSON = Get-SmaGlobalFromFile -FilePath $AssetFile.FullName -GlobalType Schedules
        if($VariableJSON)
        {
            Foreach($VariableName in (ConvertFrom-PSCustomObject(ConvertFrom-JSON $VariableJSON)).Keys)
            {
                $Assets.Variable += $VariableName
            }
        }
        if($ScheduleJSON)
        {
            Foreach($ScheduleName in (ConvertFrom-PSCustomObject(ConvertFrom-JSON $ScheduleJSON)).Keys)
            {
                $Assets.Schedule += $ScheduleName
            }
        }
    }
    Return $Assets
}
<#
    .Synopsis 
        Groups all files that will be processed.
        # TODO put logic for import order here
        # TODO Remove duplicates
    .Parameter Files
        The files to sort
    .Parameter RepositoryInformation
#>
Function Group-RepositoryFile
{
    Param([Parameter(Mandatory=$True)] $Files,
          [Parameter(Mandatory=$True)] $RepositoryInformation)
    Write-Verbose -Message 'Starting [Group-RepositoryFile]'
    $_Files = ConvertTo-Hashtable -InputObject $Files -KeyName FileExtension
    $ReturnObj = @{ 'ScriptFiles' = @() ;
                    'SettingsFiles' = @() ;
                    'ModuleFiles' = @() ;
                    'CleanRunbooks' = $False ;
                    'CleanAssets' = $False ;
                    'CleanModules' = $False ;
                    'ModulesUpdated' = $False }

    # Process PS1 Files
    try
    {
        $PowerShellScriptFiles = ConvertTo-HashTable $_Files.'.ps1' -KeyName 'FileName'
        Write-Verbose -Message 'Found Powershell Files'
        foreach($ScriptName in $PowerShellScriptFiles.Keys)
        {
            if($PowerShellScriptFiles."$ScriptName".ChangeType -contains 'M' -or
               $PowerShellScriptFiles."$ScriptName".ChangeType -contains 'A')
            {
                foreach($Path in $PowerShellScriptFiles."$ScriptName".FullPath)
                {
                    if($Path -like "$($RepositoryInformation.Path)\$($RepositoryInformation.RunbookFolder)\*")
                    {
                        $ReturnObj.ScriptFiles += $Path
                        break
                    }
                }            
            }
            else
            {
                $ReturnObj.CleanRunbooks = $True
            }
        }
    }
    catch
    {
        Write-Verbose -Message 'No Powershell Files found'
    }
    try
    {
        # Process Settings Files
        $SettingsFiles = ConvertTo-HashTable $_Files.'.json' -KeyName 'FileName'
        Write-Verbose -Message 'Found Settings Files'
        foreach($SettingsFileName in $SettingsFiles.Keys)
        {
            if($SettingsFiles."$SettingsFileName".ChangeType -contains 'M' -or
               $SettingsFiles."$SettingsFileName".ChangeType -contains 'A')
            {
                foreach($Path in $SettingsFiles."$SettingsFileName".FullPath)
                {
                    if($Path -like "$($RepositoryInformation.Path)\$($RepositoryInformation.RunbookFolder)\*")
                    {
                        $ReturnObj.CleanAssets = $True
                        $ReturnObj.SettingsFiles += $Path
                        break
                    }
                }
            }
            else
            {
                $ReturnObj.CleanAssets = $True
            }
        }
    }
    catch
    {
        Write-Verbose -Message 'No Settings Files found'
    }
    try
    {
        $PSModuleFiles = ConvertTo-HashTable $_Files.'.psd1' -KeyName 'FileName'
        Write-Verbose -Message 'Found Powershell Module Files'
        foreach($PSModuleName in $PSModuleFiles.Keys)
        {
            if($PSModuleFiles."$PSModuleName".ChangeType -contains 'M' -or
               $PSModuleFiles."$PSModuleName".ChangeType -contains 'A')
            {
                foreach($Path in $PSModuleFiles."$PSModuleName".FullPath)
                {
                    if($Path -like "$($RepositoryInformation.Path)\$($RepositoryInformation.PowerShellModuleFolder)\*")
                    {
                        $ReturnObj.ModulesUpdated = $True
                        $ReturnObj.ModuleFiles += $Path
                        break
                    }
                }
            }
            else
            {
                $ReturnObj.CleanModules = $True
            }
        }
    }
    catch
    {
        Write-Verbose -Message 'No Powershell Module Files found'
    }
    Write-Verbose -Message 'Finished [Group-RepositoryFile]'
    Return (ConvertTo-JSON $ReturnObj -Compress)
}
<#
    .Synopsis
        Groups a list of SmaRunbooks by the RepositoryName from the
        tag line
#>
Function Group-SmaRunbooksByRepository
{
    Param([Parameter(Mandatory=$True)] $InputObject)
    ConvertTo-Hashtable -InputObject $InputObject `
                        -KeyName 'Tags' `
                        -KeyFilterScript { 
                            Param($KeyName)
                            if($KeyName -match 'RepositoryName:([^;]+);')
                            {
                                $Matches[1]
                            }
                        }
}
<#
    .Synopsis
        Groups a list of SmaRunbooks by the RepositoryName from the
        tag line
#>
Function Group-SmaAssetsByRepository
{
    Param([Parameter(Mandatory=$True)] $InputObject)
    ConvertTo-Hashtable -InputObject $InputObject `
                        -KeyName 'Description' `
                        -KeyFilterScript { 
                            Param($KeyName)
                            if($KeyName -match 'RepositoryName:([^;]+);')
                            {
                                $Matches[1]
                            }
                        }
}
<#
    .Synopsis
        Check the target Git Repo / Branch for any updated files. 
        Ingores files in the root
    
    .Parameter RepositoryInformation
        The PSCustomObject containing repository information
#>
Function Find-GitRepositoryChange
{
    Param([Parameter(Mandatory=$true) ] $RepositoryInformation)
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    
    # Set current directory to the git repo location
    Set-Location $RepositoryInformation.Path
      
    $ReturnObj = @{ 'CurrentCommit' = $RepositoryInformation.CurrentCommit;
                    'Files' = @() }
    
    $NewCommit = (git rev-parse --short HEAD)
    $ModifiedFiles = git diff --name-status (Select-FirstValid -Value $RepositoryInformation.CurrentCommit, (git rev-list --max-parents=0 HEAD) -FilterScript { $_ -ne -1 }) $NewCommit
    $ReturnObj = @{ 'CurrentCommit' = $NewCommit ; 'Files' = @() }
    Foreach($File in $ModifiedFiles)
    {
        if("$($File)" -Match '([a-zA-Z])\s+(.+\/([^\./]+(\..+)))$')
        {
            $ReturnObj.Files += @{ 'FullPath' = "$($RepositoryInformation.Path)\$($Matches[2].Replace('/','\'))" ;
                                   'FileName' = $Matches[3] ;
                                   'FileExtension' = $Matches[4].ToLower()
                                   'ChangeType' = $Matches[1] }
        }
    }
    
    return (ConvertTo-Json $ReturnObj -Compress)
}
<#
    .Synopsis
        Updates a git repository to the latest version
    
    .Parameter RepositoryInformation
        The PSCustomObject containing repository information
#>
Function Update-GitRepository
{
    Param([Parameter(Mandatory=$true) ] $RepositoryInformation)
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    
    # Set current directory to the git repo location
    Set-Location $RepositoryInformation.Path
      
    if(-not ("$(git branch)" -match '\*\s(\w+)'))
    {
        Throw-Exception -Type 'GitTargetBranchNotFound' `
                        -Message 'git could not find any current branch' `
                        -Property @{ 'result' = $(git branch) ;
                                     'match'  = "$(git branch)" -match '\*\s(\w+)'}
    }
    if($Matches[1] -ne $RepositoryInformation.Branch)
    {
        Write-Verbose -Message "Setting current branch to [$($RepositoryInformation.Branch)]"
        try
        {
            git checkout $RepositoryInformation.Branch | Out-Null
        }
        catch
        {
            if($LASTEXITCODE -ne 0)
            {
                Write-Exception -Stream Error -Exception $_
            }
            else
            {
                Write-Exception -Stream Verbose -Exception $_
            }
        }
    }

    
    try
    {
        $initialization = git pull
    }
    catch
    {
        if($LASTEXITCODE -ne -1)
        {
            Write-Verbose -Message "`$LASTEXITCODE [$LASTEXITCODE]"
            Write-Exception -Stream Error -Exception $_
        }
        else
        {
            Write-Verbose -Message 'Updated Repository'
        }
    }
}
Export-ModuleMember -Function * -Verbose:$false -Debug:$False
# SIG # Begin signature block
# MIIOfQYJKoZIhvcNAQcCoIIObjCCDmoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU5s37vt3AMT5GMZzioO+rrE0w
# Wz2gggqQMIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# CisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQAOYkm
# glnifiWMST2hnxwJ2r9trTANBgkqhkiG9w0BAQEFAASBgK1cPhjsqvei13nz4kRI
# sf/uMLBmPj9zIIWbG+NWkbQoVKvC9QAimrpnLA6BZhnClLL7aK4xW5r7YvU9tsxW
# zJdWVQdASw/1H2bOk1SiTheMQCIO+E/Sz1Z430rc0Th79vdAnmuFNUEllfm4Rj7q
# roaGmKGw7mgvzmcnG/4535rRoYICCzCCAgcGCSqGSIb3DQEJBjGCAfgwggH0AgEB
# MHIwXjELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9u
# MTAwLgYDVQQDEydTeW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0g
# RzICEA7P9DjI/r81bgTYapgbGlAwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJAzEL
# BgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1MDMxNjIwMDY1MVowIwYJKoZI
# hvcNAQkEMRYEFL4fcVcELk68/B1/zHra86Kz2YisMA0GCSqGSIb3DQEBAQUABIIB
# ACAnmaqVeRC12DBXPceLekasqTBmHbAIpdlMxoMv7yZPLgQhPePRFRdb5iqbuSf5
# dM675brzmazKMTfmrBX2LUkv425RBYEuy0LPyVEeHnvkTokVf1sT2RvJGf+Aiols
# P0KlNUnG927vzmFhkaf4zD/R5z22azgPcT9M8XJNv6zWJLEDliDD4wp3RdDGZ9us
# M9ZPN/sCAGqyX1L0aPn85ICxEVYgyiNeVkYewncONOnaWP/vWnv506q6ZmMQKhHy
# uMbXOEsYUpigDpdwtfxf8qSAkbEkxOmQ6DWNO3ASk6qYq6DUAGAciv7YpdSg4hFA
# GECsTk7ETMNI0ypg2wGq+cM=
# SIG # End signature block
