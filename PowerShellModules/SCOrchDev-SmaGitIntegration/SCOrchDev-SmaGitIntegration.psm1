<#
    .Synopsis
        Looks for the tag workflow in a file and returns the next string
    
    .Parameter FilePath
        The path to the file to search
#>
Function Get-SmaWorkflowNameFromFile
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
    $FileContent = Get-Content $FilePath
    Throw-Exception -Type 'WorkflowNameNotFound' `
                        -Message 'Could not find the workflow tag and corresponding workflow name' `
                        -Property @{ 'FileContent' = "$FileContent" }
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
    if(-Not (Test-Path -Path $RepositoryInformation.Path))
    {
        $ParentDirectory = New-FileItemContainer -FileItemPath $RepositoryInformation.Path
        Try
        {
            git.exe clone "$($RepositoryInformation.RepositoryPath)" "$($RepositoryInformation.Path)" --recursive
        }
        Catch
        {
            Write-Exception -Exception $_ -Stream Warning 
        }
        
    }
    Set-Location $RepositoryInformation.Path
      
    if(-not ("$(git.exe branch)" -match '\*\s(\w+)'))
    {
        if(Test-IsNullOrEmpty -String "$(git.exe branch)")
        {
            Write-Verbose -Message 'git branch did not return output. Assuming we are on the correct branch'
        }
        else
        {
            Throw-Exception -Type 'GitTargetBranchNotFound' `
                            -Message 'git could not find any current branch' `
                            -Property @{ 'result' = $(git.exe branch) ;
                                         'match'  = "$(git.exe branch)" -match '\*\s(\w+)'}
        }
    }
    elseif($Matches[1] -ne $RepositoryInformation.Branch)
    {
        Write-Verbose -Message "Setting current branch to [$($RepositoryInformation.Branch)]"
        try
        {
            git.exe checkout $RepositoryInformation.Branch | Out-Null
        }
        catch
        {
            Write-Exception -Exception $_ -Stream Warning
        }
    }
    
    try
    {
        $initialization = git.exe pull
    }
    catch
    {
        Write-Exception -Exception $_ -Stream Warning
    }
}
Export-ModuleMember -Function * -Verbose:$false -Debug:$False
# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUej7D5epkugTFK/bLeJWSU1W7
# Ul6gggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUcD1k5dBroVFdcwGCp+EOvUfVSMgwDQYJKoZIhvcNAQEBBQAEgYC7jSbuTDSL
# G2X9HjfDH3Ojvh9iJ9r1/BAbZ9VBPL5MA0en/05v6FY+GI42jImyuWAf6lAP4w/2
# glL5FU+rZqJofgg0V5gK5KRIrOdAYbPJeZw+ERK3aN2F5HKdESBuzwj5jjY2nip/
# 6jTxOrjAnsqcsex/ohXiYcpOkM0APTOK4A==
# SIG # End signature block
