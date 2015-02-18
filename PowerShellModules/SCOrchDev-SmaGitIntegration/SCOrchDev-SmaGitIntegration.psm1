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
    return ConvertTo-JSON @{'TagLine' = $TagLine ;
                            'NewVersion' = $NewVersion }
}
<#
    .Synopsis
        Returns all variables in a JSON settings file

    .Parameter FilePath
        The path to the JSON file containing SMA settings
#>
Function Get-SmaVariablesFromFile
{
    Param([Parameter(Mandatory=$false)][string] $FilePath)

    $FileContent = Get-Content $FilePath
    $Variables = ConvertFrom-PSCustomObject ((ConvertFrom-Json ((Get-Content -Path $FilePath) -as [String])).Variables)

    if(Test-IsNullOrEmpty $Variables.Keys)
    {
        Write-Warning -Message "No variables root in folder"
    }

    return ConvertTo-JSON $Variables
}
<#
    .Synopsis
        Returns all Schedules in a JSON settings file

    .Parameter FilePath
        The path to the JSON file containing SMA settings
#>
Function Get-SmaSchedulesFromFile
{
    Param([Parameter(Mandatory=$false)][string] $FilePath)

    $FileContent = Get-Content $FilePath
    $Variables = ConvertFrom-PSCustomObject ((ConvertFrom-Json ((Get-Content -Path $FilePath) -as [String])).Schedules)

    if(Test-IsNullOrEmpty $Variables.Keys)
    {
        Write-Warning -Message "No Schedules root in folder"
    }

    return ConvertTo-JSON $Variables
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

    
    $RepositoryInformation = (ConvertFrom-JSON $RepositoryInformation)
    $RepositoryInformation."$RepositoryName".CurrentCommit = $Commit

    return (ConvertTo-Json $RepositoryInformation)
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
        Foreach($Variable in (Get-SmaVariablesFromFile -FilePath $AssetFile.FullName))
        {
            $Assets.Variable += (ConvertFrom-Json $Variable).name
        }
        Foreach($Schedule in (Get-SmaSchedulesFromFile -FilePath $AssetFile.FullName))
        {
            $Assets.Schedule += (ConvertFrom-Json $Variable).name
        }
    }
    Return $Assets
}
<#
    .Synopsis 
        Groups all files that will be processed.
        # TODO put logic for import order here
        # TODO Remove duplicates
    .Files
        The files to sort
#>
Function Group-RepositoryFile
{
    Param([Parameter(Mandatory=$True)] $Files)

    $_Files = ConvertTo-Hashtable -InputObject $Files -KeyName FileExtension
    $ReturnObj = @{ 'ScriptFiles' = @() ;
                    'SettingsFiles' = @() ;
                    'CleanRunbooks' = $False ;
                    'CleanAssets' = $False }

    # Process PS1 Files
    $PowerShellScriptFiles = ConvertTo-HashTable $_Files.'.ps1' -KeyName 'FileName'
    foreach($ScriptName in $PowerShellScriptFiles.Keys)
    {
        if($PowerShellScriptFiles."$ScriptName".ChangeType -contains 'M' -or
           $PowerShellScriptFiles."$ScriptName".ChangeType -contains 'A')
        {
            $ReturnObj.ScriptFiles += $PowerShellScriptFiles."$ScriptName"[0].FullPath
        }
        else
        {
            $ReturnObj.CleanRunbooks = $True
        }
    }

    # Process Settings Files
    $SettingsFiles = ConvertTo-HashTable $_Files.'.json' -KeyName 'FileName'
    foreach($SettingsFileName in $SettingsFiles.Keys)
    {
        if($SettingsFiles."$SettingsFileName".ChangeType -contains 'M' -or
           $SettingsFiles."$SettingsFileName".ChangeType -contains 'A')
        {
            $ReturnObj.SettingsFiles += $SettingsFiles."$SettingsFileName"[0].FullPath
        }
        else
        {
            $ReturnObj.CleanAssets = $True
        }
    }

    Return (ConvertTo-JSON $ReturnObj)
}
Export-ModuleMember -Function * -Verbose:$false -Debug:$False