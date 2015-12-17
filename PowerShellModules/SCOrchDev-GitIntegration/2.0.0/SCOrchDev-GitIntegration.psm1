#requires -Version 3 -Modules SCOrchDev-Exception, SCOrchDev-File, SCOrchDev-Utility
if(-not $env:Path -match '([^;]*Git\\cmd);')
{
    Throw-Exception -Type 'gitExeNotFound' `
                    -Message 'Could not find the git executable in the local computer''s path'
}
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
    return (ConvertTo-JSON -InputObject @{'TagLine' = $TagLine ;
                                          'NewVersion' = $NewVersion } `
                           -Compress)
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
        Write-Exception -Exception $_ -Stream Warning
    }

    return (ConvertTo-JSON -InputObject $ReturnInformation -Compress)
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
Function Set-RepositoryInformationCommitVersion
{
    Param([Parameter(Mandatory=$false)][string] $RepositoryInformation = [string]::EmptyString,
          [Parameter(Mandatory=$false)][string] $RepositoryName = [string]::EmptyString,
          [Parameter(Mandatory=$false)][string] $Commit = [string]::EmptyString)
    
    $_RepositoryInformation = (ConvertFrom-JSON -InputObject $RepositoryInformation)
    $_RepositoryInformation."$RepositoryName".CurrentCommit = $Commit

    return (ConvertTo-Json -InputObject $_RepositoryInformation -Compress)
}
Function Get-GitRepositoryWorkflowName
{
    Param([Parameter(Mandatory=$false)][string] $Path = [string]::EmptyString)

    $RunbookNames = @()
    $RunbookFiles = Get-ChildItem -Path $Path `
                                  -Filter '*.ps1' `
                                  -Recurse `
                                  -File
    foreach($RunbookFile in $RunbookFiles)
    {
        $RunbookNames += Get-WorkflowNameFromFile -FilePath $RunbookFile.FullName
    }
    $RunbookNames
}
Function Get-GitRepositoryVariableName
{
    Param([Parameter(Mandatory=$false)][string] $Path = [string]::EmptyString)

    $RunbookNames = @()
    $RunbookFiles = Get-ChildItem -Path $Path `
                                  -Filter '*.json' `
                                  -Recurse `
                                  -File
    foreach($RunbookFile in $RunbookFiles)
    {
        $RunbookNames += Get-WorkflowNameFromFile -FilePath $RunbookFile.FullName
    }
    Return $RunbookNames
}
Function Get-GitRepositoryAssetName
{
    Param([Parameter(Mandatory=$false)][string] $Path = [string]::EmptyString)

    $Assets = @{ 'Variable' = @() ;
                 'Schedule' = @() }
    $AssetFiles = Get-ChildItem -Path $Path `
                                  -Filter '*.json' `
                                  -Recurse `
                                  -File
    
    foreach($AssetFile in $AssetFiles)
    {
        $VariableJSON = Get-GlobalFromFile -FilePath $AssetFile.FullName -GlobalType Variables
        $ScheduleJSON = Get-GlobalFromFile -FilePath $AssetFile.FullName -GlobalType Schedules
        if($VariableJSON)
        {
            Foreach($VariableName in (ConvertFrom-PSCustomObject -InputObject (ConvertFrom-JSON -InputObject $VariableJSON)).Keys)
            {
                $Assets.Variable += $VariableName
            }
        }
        if($ScheduleJSON)
        {
            Foreach($ScheduleName in (ConvertFrom-PSCustomObject -InputObject (ConvertFrom-JSON -InputObject $ScheduleJSON)).Keys)
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
        $PowerShellScriptFiles = ConvertTo-HashTable -InputObject $_Files.'.ps1' -KeyName 'FileName'
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
        $SettingsFiles = ConvertTo-HashTable -InputObject $_Files.'.json' -KeyName 'FileName'
        Write-Verbose -Message 'Found Settings Files'
        foreach($SettingsFileName in $SettingsFiles.Keys)
        {
            if($SettingsFiles."$SettingsFileName".ChangeType -contains 'M' -or
               $SettingsFiles."$SettingsFileName".ChangeType -contains 'A')
            {
                foreach($Path in $SettingsFiles."$SettingsFileName".FullPath)
                {
                    if($Path -like "$($RepositoryInformation.Path)\$($RepositoryInformation.GlobalsFolder)\*")
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
        $PSModuleFiles = ConvertTo-HashTable -InputObject $_Files.'.psd1' -KeyName 'FileName'
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
    Return (ConvertTo-JSON -InputObject $ReturnObj -Compress)
}
<#
    .Synopsis
        Groups a list of Runbooks by the RepositoryName from the
        tag line
#>
Function Group-RunbooksByRepository
{
    Param([Parameter(Mandatory=$True)] $InputObject)
    ConvertTo-Hashtable -InputObject $InputObject `
                        -KeyName 'Tags' `
                        -KeyFilterScript { 
                            Param($KeyName)
                            if($KeyName -match 'RepositoryName:(.+)')
                            {
                                $Matches[1]
                            }
                        }
}
<#
    .Synopsis
        Groups a list of Runbooks by the RepositoryName from the
        tag line
#>
Function Group-AssetsByRepository
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
    $CurrentLocation = Get-Location
    try
    {
        Set-Location -Path $RepositoryInformation.Path

        $ReturnObj = @{ 'CurrentCommit' = $RepositoryInformation.CurrentCommit;
                        'Files' = @() }
    
        $NewCommit = (Invoke-Expression -Command "$($gitExe) rev-parse --short HEAD") -as  [string]
        $FirstRepoCommit = (Invoke-Expression -Command "$($gitExe) rev-list --max-parents=0 HEAD") -as [string]
        $StartCommit = (Select-FirstValid -Value $RepositoryInformation.CurrentCommit, $FirstRepoCommit -FilterScript { $_ -ne -1 }) -as [string]
        $ModifiedFiles = Invoke-Expression -Command "$($gitExe) diff --name-status $StartCommit $NewCommit"
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
    }
    catch
    {
        throw
    }
    finally
    {
        Set-Location -Path $CurrentLocation
    }
    
    return (ConvertTo-Json -InputObject $ReturnObj -Compress)
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
    Write-Verbose -Message 'Starting [Update-GitRepository]'
    # Set current directory to the git repo location
    if(-Not (Test-Path -Path $RepositoryInformation.Path))
    {
        $null = New-FileItemContainer -FileItemPath $RepositoryInformation.Path
        Try
        {
            Write-Verbose -Message 'Cloneing repository'
            Invoke-Expression -Command "$gitEXE clone $($RepositoryInformation.RepositoryPath) $($RepositoryInformation.Path) --recursive"
        }
        Catch
        {
            Write-Exception -Exception $_ -Stream Warning 
        }
        
    }
    $CurrentLocation = Get-Location
    Set-Location -Path $RepositoryInformation.Path

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
    elseif($Matches[1] -ne $RepositoryInformation.Branch)
    {
        Write-Verbose -Message "Setting current branch to [$($RepositoryInformation.Branch)]"
        try
        {
            Write-Verbose -Message "Changing branch to [$($RepositoryInformation.Branch)]"
            (Invoke-Expression -Command "$gitEXE checkout $($RepositoryInformation.Branch)") | Out-Null
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
        Switch($ExceptionInformation.Type)
        {
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
    Write-Verbose -Message 'Finished [Update-GitRepository]'
}
Export-ModuleMember -Function * -Verbose:$false -Debug:$False