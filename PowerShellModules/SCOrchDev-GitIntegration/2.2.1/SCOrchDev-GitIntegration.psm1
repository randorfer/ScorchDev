#requires -Version 3 -Modules SCOrchDev-Exception, SCOrchDev-File, SCOrchDev-Utility
$gitEXE = 'git.exe'

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
Function New-ChangesetTagLine
{
    Param([Parameter(Mandatory=$false)][string] $TagLine = [string]::EmptyString,
          [Parameter(Mandatory=$true)][string]  $CurrentCommit,
          [Parameter(Mandatory=$true)][string]  $RepositoryName)
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage -Stream Debug
    $NewVersion = $False
    if(($TagLine -as [string]) -match 'CurrentCommit:([^;]+);')
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
    if(($TagLine -as [string]) -match 'RepositoryName:([^;]+);')
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
    Write-CompletedMessage @CompletedParameters
    return @{'TagLine' = $TagLine ;
             'NewVersion' = $NewVersion }
}
<#
    .Synopsis
        Returns all variables in a JSON settings file

    .Parameter FilePath
        The path to the JSON file containing settings
#>
Function Get-GlobalFromFile
{
    Param([Parameter(Mandatory=$false)]
          [string] 
          $FilePath = [string]::EmptyString,
          
          [ValidateSet('Variables','Schedules')]
          [Parameter(Mandatory=$false)]
          [string] 
          $GlobalType = 'Variables')
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage -Stream Debug
    $ReturnInformation = @{}
    try
    {
        $SettingsJSON = (Get-Content -Path $FilePath) -as [string]
        $SettingsObject = ConvertFrom-Json -InputObject $SettingsJSON
        $SettingsHashTable = ConvertFrom-PSCustomObject -InputObject $SettingsObject
        
        if(-not ($SettingsHashTable.ContainsKey($GlobalType)))
        {
            Throw-Exception -Type 'GlobalTypeNotFound' `
                            -Message 'Global Type not found in settings file.' `
                            -Property @{ 'FilePath' = $FilePath ;
                                         'GlobalType' = $GlobalType ;
                                         'SettingsJSON' = $SettingsJSON }
        }

        $GlobalTypeObject = $SettingsHashTable."$GlobalType"
        $GlobalTypeHashTable = ConvertFrom-PSCustomObject -InputObject $GlobalTypeObject -ErrorAction SilentlyContinue

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
        Write-Exception -Exception $_ -Stream Debug
    }
    Write-CompletedMessage @CompletedParameters
    return $ReturnInformation
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
Function Update-RepositoryInformationCommitVersion
{
    Param([Parameter(Mandatory=$false)][string] $RepositoryInformationJSON = [string]::EmptyString,
          [Parameter(Mandatory=$false)][string] $RepositoryName = [string]::EmptyString,
          [Parameter(Mandatory=$false)][string] $Commit = [string]::EmptyString)
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage -Stream Debug
    $_RepositoryInformation = (ConvertFrom-JSON -InputObject $RepositoryInformationJSON)
    $_RepositoryInformation."$RepositoryName".CurrentCommit = $Commit
    Write-CompletedMessage @CompletedParameters
    return (ConvertTo-Json -InputObject $_RepositoryInformation -Compress)
}
Function Get-GitRepositoryRunbookName
{
    Param([Parameter(Mandatory=$false)][string] $Path = [string]::EmptyString)
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage -Stream Debug
    $RunbookNames = @()
    $RunbookFiles = Get-ChildItem -Path $Path `
                                  -Filter '*.ps1' `
                                  -Recurse `
                                  -File
    foreach($RunbookFile in $RunbookFiles)
    {
        if(Test-FileIsWorkflow -FilePath $RunbookFile.FullName)
        {
            $RunbookNames += Get-WorkflowNameFromFile -FilePath $RunbookFile.FullName
        }
        else
        {
            $RunbookNames += Get-ScriptNameFromFileName -FilePath $RunbookFile.FullName
        }
        
    }
    Write-CompletedMessage @CompletedParameters
    $RunbookNames
}
Function Get-GitRepositoryVariableName
{
    Param([Parameter(Mandatory=$false)][string] $Path = [string]::EmptyString)
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage -Stream Debug
    $RunbookNames = @()
    $RunbookFiles = Get-ChildItem -Path $Path `
                                  -Filter '*.json' `
                                  -Recurse `
                                  -File
    foreach($RunbookFile in $RunbookFiles)
    {
        $RunbookNames += Get-WorkflowNameFromFile -FilePath $RunbookFile.FullName
    }
    Write-CompletedMessage @CompletedParameters
    Return $RunbookNames
}
Function Get-GitRepositoryAssetName
{
    Param([Parameter(Mandatory=$false)][string] $Path = [string]::EmptyString)
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage -Stream Debug
    $Assets = @{ 'Variable' = @() ;
                 'Schedule' = @() }
    $AssetFiles = Get-ChildItem -Path $Path `
                                  -Filter '*.json' `
                                  -Recurse `
                                  -File
    
    foreach($AssetFile in $AssetFiles)
    {
        $Variable = Get-GlobalFromFile -FilePath $AssetFile.FullName -GlobalType Variables
        $Schedule = Get-GlobalFromFile -FilePath $AssetFile.FullName -GlobalType Schedules
        if($Variable -as [bool])
        {
            Foreach($VariableName in $Variable.Keys)
            {
                $Assets.Variable += $VariableName
            }
        }
        if($Schedule -as [bool])
        {
            Foreach($ScheduleName in $Schedule.Keys)
            {
                $Assets.Schedule += $ScheduleName
            }
        }
    }
    Write-CompletedMessage @CompletedParameters
    Return $Assets
}
<#
    .Synopsis 
        Groups all files that will be processed.
        # TODO put logic for import order here
    .Parameter Files
        The files to sort
    .Parameter Path
        The path to the git repository root
    .Parameter RunbookFolder
        The name of the folder with runbooks inside
    .Parameter GlobalsFolder
        The name of the folder with globals inside
    .Parameter PowerShellModuleFolder
        The name of the folder with PowerShell modules inside
#>
Function Group-RepositoryFile
{
    Param(
        [Parameter(Mandatory=$True)]
        $File,
    
        [Parameter(Mandatory=$True)]
        [string]
        $Path,

        [Parameter(Mandatory=$True)]
        [string]
        $RunbookFolder,

        [Parameter(Mandatory=$True)]
        [string]
        $GlobalsFolder,

        [Parameter(Mandatory=$True)]
        [string]
        $PowerShellModuleFolder,

        [Parameter(Mandatory=$True)]
        [string]
        $DSCFolder
    )
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage
    $_File = ConvertTo-Hashtable -InputObject $File -KeyName FileExtension
    $ReturnObj = @{ 'ScriptFiles' = @() ;
                    'SettingsFiles' = @() ;
                    'ModuleFiles' = @() ;
                    'DSCFiles' = @() ;
                    'CleanDSC' = $False ;
                    'CleanRunbooks' = $False ;
                    'CleanAssets' = $False ;
                    'CleanModules' = $False ;
                    'ModulesUpdated' = $False }

    # Process PS1 Files
    try
    {
        $PowerShellScriptFiles = ConvertTo-HashTable -InputObject $_File.'.ps1' -KeyName 'FileName'
        if(($PowerShellScriptFiles -as [bool]) -and ($PowerShellScriptFiles.Keys -as [array]).Count -gt 0)
        {
            Write-Verbose -Message 'Found Powershell Files'
            foreach($ScriptName in $PowerShellScriptFiles.Keys)
            {
                if($PowerShellScriptFiles."$ScriptName".ChangeType -contains 'M' -or
                   $PowerShellScriptFiles."$ScriptName".ChangeType -contains 'A')
                {
                    foreach($FullPath in $PowerShellScriptFiles."$ScriptName".FullPath)
                    {
                        if($FullPath -like "$($Path)\$($RunbookFolder)\*")
                        {
                            $ReturnObj.ScriptFiles += $FullPath
                            break
                        }
                        if($FullPath -like "$($Path)\$($DSCFolder)\*")
                        {
                            $ReturnObj.DSCFiles += $FullPath
                            break
                        }
                    }            
                }
                else
                {
                    foreach($FullPath in $PowerShellScriptFiles."$ScriptName".FullPath)
                    {
                        if($FullPath -like "$($Path)\$($RunbookFolder)\*")
                        {
                            $ReturnObj.CleanRunbooks = $True
                            break
                        }
                        if($FullPath -like "$($Path)\$($DSCFolder)\*")
                        {
                            $ReturnObj.CleanDSC = $True
                            break
                        }
                    } 
                }
            }
        }
        else
        {
            Write-Verbose -Message 'No Powershell Files found'
        }
    }
    catch
    {
        Write-Verbose -Message 'No Powershell Files found'
    }
    try
    {
        # Process Settings Files
        $SettingsFiles = ConvertTo-HashTable -InputObject $_File.'.json' -KeyName 'FileName'
        if(($SettingsFiles -as [bool]) -and ($SettingsFiles.Keys -as [array]).Count -gt 0)
        {
            Write-Verbose -Message 'Found Settings Files'
            foreach($SettingsFileName in $SettingsFiles.Keys)
            {
                if($SettingsFiles."$SettingsFileName".ChangeType -contains 'M' -or
                   $SettingsFiles."$SettingsFileName".ChangeType -contains 'A')
                {
                    foreach($FullPath in $SettingsFiles."$SettingsFileName".FullPath)
                    {
                        if($FullPath -like "$($Path)\$($GlobalsFolder)\*")
                        {
                            $ReturnObj.CleanAssets = $True
                            $ReturnObj.SettingsFiles += $FullPath
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
        else
        {
            Write-Verbose -Message 'No Settings Files found'
        }
    }
    catch
    {
        Write-Verbose -Message 'No Settings Files found'
    }
    try
    {
        $PSModuleFiles = ConvertTo-HashTable -InputObject $_File.'.psd1' -KeyName 'FileName'
        if(($PSModuleFiles -as [bool]) -and ($PSModuleFiles.Keys -as [array]).Count -gt 0)
        {
            Write-Verbose -Message 'Found Powershell Module Files'
            foreach($PSModuleName in $PSModuleFiles.Keys)
            {
                if($PSModuleFiles."$PSModuleName".ChangeType -contains 'M' -or
                   $PSModuleFiles."$PSModuleName".ChangeType -contains 'A')
                {
                    foreach($FullPath in $PSModuleFiles."$PSModuleName".FullPath)
                    {
                        if($FullPath -like "$($Path)\$($PowerShellModuleFolder)\*")
                        {
                            $ReturnObj.ModulesUpdated = $True
                            $ReturnObj.ModuleFiles += $FullPath
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
        else
        {
            Write-Verbose -Message 'No Powershell Module Files found'
        }
    }
    catch
    {
        Write-Verbose -Message 'No Powershell Module Files found'
    }
    Write-CompletedMessage @CompletedParameters -Status ($ReturnObj | ConvertTo-Json)
    Return $ReturnObj
}
<#
    .Synopsis
        Groups a list of Runbooks by the RepositoryName from the
        tag line
#>
Function Group-RunbooksByRepository
{
    Param([Parameter(Mandatory=$True)] $InputObject)
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage -Stream Debug
    ConvertTo-Hashtable -InputObject $InputObject `
                        -KeyName 'Tags' `
                        -KeyFilterScript { 
                            Param($Tags)
                            if($Tags.ContainsKey('RepositoryName')) { $Tags.RepositoryName }
                        }
    Write-CompletedMessage @CompletedParameters
}
<#
    .Synopsis
        Groups a list of Runbooks by the RepositoryName from the
        tag line
#>
Function Group-AssetsByRepository
{
    Param([Parameter(Mandatory=$True)] $InputObject)
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage -Stream Debug
    ConvertTo-Hashtable -InputObject $InputObject `
                        -KeyName 'Description' `
                        -KeyFilterScript { 
                            Param($KeyName)
                            if($KeyName -match 'RepositoryName:([^;]+);')
                            {
                                $Matches[1]
                            }
                        }
    Write-CompletedMessage @CompletedParameters
}
<#
    .Synopsis
        Check the target Git Repo / Branch for any updated files. 
        Ingores files in the root
    
    .Parameter Path
        The path of the mapped repository

    .Parameter StartCommit
        The commit find changes since
#>
Function Find-GitRepositoryChange
{
    Param(
        [Parameter(
            Mandatory=$true
        )]
        [string]
        $Path,
        
        [Parameter(
            Mandatory=$false
        )]
        [string]
        $StartCommit = -1
    )
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage -String "StartCommit [$StartCommit]"
    
    # Set current directory to the git repo location
    $CurrentLocation = Get-Location
    try
    {
        Set-Location -Path $Path

        $ReturnObj = @{ 'CurrentCommit' = $CurrentCommit;
                        'Files' = @() }
        
        $NewCommit = Get-GitCurrentCommit -Path $Path
        $FirstRepoCommit = Get-GitInitialCommit -Path $Path
        $StartCommit = (Select-FirstValid -Value $StartCommit, $FirstRepoCommit -FilterScript { $_ -ne -1 }) -as [string]
        $ModifiedFiles = Get-GitModifiedFile -Path $Path -StartCommit $StartCommit -NewCommit $NewCommit
        $ReturnObj = @{ 'CurrentCommit' = $NewCommit ; 'Files' = @() }
        Foreach($File in $ModifiedFiles)
        {
            if("$($File)" -Match '([a-zA-Z])\s+(.+(\..+))$')
            {
                $FileInfo = ("$((Get-Location).Path)\$($Matches[2].Replace('/','\'))") -as [System.IO.FileInfo]
                $ReturnObj.Files += @{ 
                    'FullPath' = "$($FileInfo.FullName)"
                    'FileName' = $FileInfo.Name
                    'FileExtension' = $FileInfo.Extension
                    'ChangeType' = $Matches[1]
                }
            }
        }
        $ReturnObj.Files += Get-GitSumboduleFileChange -StartCommit $StartCommit
    }
    catch
    {
        throw
    }
    finally
    {
        Set-Location -Path $CurrentLocation
    }
    Write-CompletedMessage @CompletedParameters -Status ($ReturnObj | ConvertTo-Json)
    return $ReturnObj
}
Function Get-GitModifiedFile
{
    Param(
        [Parameter(
            Mandatory=$true
        )]
        [string]
        $Path,

        [Parameter(
            Mandatory=$true
        )]
        [string]
        $StartCommit,

        [Parameter(
            Mandatory=$true
        )]
        [string]
        $NewCommit
    )
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage -Stream Debug
    
    # Set current directory to the git repo location
    $CurrentLocation = Get-Location
    try
    {
        Set-Location -Path $Path
        $ModifiedFiles = Invoke-Expression -Command "$($gitExe) diff --name-status $StartCommit $NewCommit"
    }
    catch
    {
        throw
    }
    finally
    {
        Set-Location -Path $CurrentLocation
    }
    Write-CompletedMessage @CompletedParameters -Status ($ModifiedFiles | ConvertTo-JSON)
    return $ModifiedFiles
}
Function Get-GitCurrentCommit
{
        Param(
        [Parameter(
            Mandatory=$true
        )]
        [string]
        $Path
    )
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage -Stream Debug
    
    # Set current directory to the git repo location
    $CurrentLocation = Get-Location
    try
    {
        Set-Location -Path $Path
        $Commit = (Invoke-Expression -Command "$($gitExe) rev-parse --short HEAD") -as [string]
    }
    catch
    {
        throw
    }
    finally
    {
        Set-Location -Path $CurrentLocation
    }
    Write-CompletedMessage @CompletedParameters -Status $Commit
    return $Commit
}
Function Get-GitInitialCommit
{
        Param(
        [Parameter(
            Mandatory=$true
        )]
        [string]
        $Path
    )
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage -Stream Debug
    
    # Set current directory to the git repo location
    $CurrentLocation = Get-Location
    try
    {
        Set-Location -Path $Path
        $Commit = (Invoke-Expression -Command "$($gitExe) rev-list --max-parents=0 HEAD") -as [string]
    }
    catch
    {
        throw
    }
    finally
    {
        Set-Location -Path $CurrentLocation
    }
    Write-CompletedMessage @CompletedParameters -Status $Commit
    return $Commit
}
<#
#>
Function Get-GitSumboduleFileChange
{
    Param(
        [Parameter(
            Mandatory=$True
        )]
        [string]
        $StartCommit
    )
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage
    
    # Set current directory to the git repo location
    $CurrentLocation = Get-Location
    try
    {
        $ReturnObj = @()
        $ModifiedSubmodule = Invoke-Expression -Command "$($gitExe) submodule summary $StartCommit" `
            | Where-Object { $_ -match '\* (.*) ([a-f0-9]+\.\.\.[a-f0-9]+)+' } | ForEach-Object {
                @{$Matches[1] = $Matches[2]}
            }

        Foreach($_ModifiedSubmodule in $ModifiedSubmodule)
        {
            try
            {
                Set-Location -Path $_ModifiedSubmodule.Keys[0]
                $FirstRepoCommit = (Invoke-Expression -Command "$($gitExe) rev-list --max-parents=0 HEAD") -as [string]
                $Commits= $_ModifiedSubmodule.Values[0].Split('.')
                $FirstCommit = $Commits[0]
                $SecondCommit = $Commits[-1]
                if($FirstCommit -eq '0000000') { $FirstCommit = $FirstRepoCommit }
                $ModifiedFiles = Invoke-Expression -Command "$($gitExe) diff --name-status $FirstCommit $SecondCommit"
                Foreach($File in $ModifiedFiles)
                {
                    if("$($File)" -Match '([a-zA-Z])\s+(.+(\..+))$')
                    {
                        $FileInfo = "$((Get-Location).Path)\$($Matches[2].Replace('/','\'))"  -as [System.IO.FileInfo]
                        $ReturnObj += @{ 
                            'FullPath' = "$($FileInfo.FullName)"
                            'FileName' = $FileInfo.Name
                            'FileExtension' = $FileInfo.Extension
                            'ChangeType' = $Matches[1]
                        }
                    }
                }
            }
            catch
            {
                Write-Exception -Exception $_ -Stream Warning
            }
            finally
            {
                Set-Location -Path $CurrentLocation
            }       
        }
    }
    catch
    {
        Write-Exception -Exception $_ -Stream Warning
    }
    finally
    {
        Set-Location -Path $CurrentLocation
    }
    Write-CompletedMessage @CompletedParameters -Status ($ReturnObj | ConvertTo-Json)
    return $ReturnObj
}
<#
    .Synopsis
        Updates a git repository to the latest version
    
    .Parameter RepositoryPath
        The path to the repository to update
            ex http://github.com/randorfer/scorchdev
    .Parameter LocalPath
        The local path to map the repository to
    .Parameter Branch
        The branch to checkout and update
#>
Function Update-GitRepository
{
    Param(
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline = $true,
            Position = 1
        )]
        [string]
        $RepositoryPath,
        
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline = $true,
            Position = 1
        )]
        [string]
        $Path,

        [Parameter(
            Mandatory=$false,
            ValueFromPipeline = $true,
            Position = 1
        )]
        [string]
        $Branch = 'master'
    )
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParameters = Write-StartingMessage
    # Set current directory to the git repo location
    if(-Not (Test-Path -Path $Path))
    {
        $null = New-FileItemContainer -FileItemPath $Path
        Try
        {
            Write-Verbose -Message 'Cloneing repository'
            Invoke-Expression -Command "$gitEXE clone $($RepositoryPath) $($Path) --recursive"
        }
        Catch
        {
            Write-Exception -Exception $_ -Stream Warning 
        }
        
    }
    $CurrentLocation = Get-Location
    Set-Location -Path $Path

    $BranchResults = (Invoke-Expression -Command "$gitEXE branch") -as [string]
    if(-not ($BranchResults -match '\*\s(\w+)'))
    {
        if(Test-IsNullOrEmpty -String $BranchResults)
        {
            Write-Verbose -Message 'git branch did not return output. Assuming we are on the correct branch'
        }
        else
        {
            Throw-Exception -Type 'GitTargetBranchNotFound' `
                            -Message 'git could not find any current branch' `
                            -Property @{ 'result' = $BranchResults ;
                                         'match'  = $BranchResults -match '\*\s(\w+)'}
        }
    }
    elseif($Matches[1] -ne $Branch)
    {
        Write-Verbose -Message "Setting current branch to [$($Branch)]"
        try
        {
            Write-Verbose -Message "Changing branch to [$($Branch)]"
            (Invoke-Expression -Command "$gitEXE checkout $($Branch)") | Out-Null
        }
        catch
        {
            Write-Exception -Exception $_ -Stream Warning
        }
    }
    
    try
    {
        $initialization = Invoke-Expression -Command "$gitEXE pull"
    }
    catch
    {
        $Exception = $_
        $ExceptionInformation = Get-ExceptionInfo -Exception $Exception
        Switch($ExceptionInformation.FullyQualifiedErrorId)
        {
            'NativeCommandError'
            {
                Write-Verbose -Message "Retrieved updates $($ExceptionInformation.Message)"
            }
            'System.Management.Automation.RemoteException'
            {
                Write-Verbose -Message "Retrieved updates $($ExceptionInformation.Message)"
            }
            Default
            {
                Write-Exception -Exception $Exception -Stream Warning
            }
        }
    }
    
    try
    {
        $initialization = Invoke-Expression -Command "$gitEXE submodule init"
    }
    catch
    {
        Write-Exception -Exception $_ -Stream Warning
    }

    try
    {
        $initialization = Invoke-Expression -Command "$gitEXE submodule update"
    }
    catch
    {
        Write-Exception -Exception $_ -Stream Warning
    }
    
    Set-Location -Path $CurrentLocation
    Write-CompletedMessage @CompletedParameters
}
Export-ModuleMember -Function * -Verbose:$false -Debug:$False