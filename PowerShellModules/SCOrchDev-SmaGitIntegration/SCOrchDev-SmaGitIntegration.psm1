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
Function Get-SmaVariablesFromFile
{
    Param([Parameter(Mandatory=$false)][string] $FilePath)

    $FileContent = Get-Content $FilePath
    $Variables = (ConvertFrom-Json ((Get-Content -Path $FilePath) -as [String])).Variables

    if(Test-IsNullOrEmpty $Variables)
    {
        Write-Warning -Message "No variables root in folder"
    }

    $returnObj = @()
    foreach($variableName in ($Variables | Get-Member -MemberType NoteProperty).Name)
    {
        $returnObj += ConvertTo-JSON @{'Name' = $variableName ;
                                       'isEncrypted' = $Variables."$variableName".isEncrypted ;
                                       'Description' = $Variables."$variableName".Description ;
                                       'Value' = $Variables."$variableName".Value}
    }
    return $returnObj
}
Function Get-SmaSchedulesFromFile
{
    Param([Parameter(Mandatory=$false)][string] $FilePath)

    $FileContent = Get-Content $FilePath
    $Schedules = (ConvertFrom-Json ((Get-Content -Path $FilePath) -as [String])).Schedules

    if(Test-IsNullOrEmpty $Schedules)
    {
        Write-Warning -Message "No Schedules root in folder"
    }
    $returnObj = @()
    foreach($scheduleName in ($Schedules | Get-Member -MemberType NoteProperty).Name)
    {
        $returnObj += ConvertTo-JSON @{'Name' = $scheduleName ;
                                       'Description' = $Schedules."$scheduleName".Description ;
                                       'DayInterval' = $Schedules."$scheduleName".DayInterval -as [int] ;
                                       'ExpirationTime' = $Schedules."$scheduleName".ExpirationTime -as [DateTime] ;
                                       'NextRun' = $Schedules."$scheduleName".NextRun -as [DateTime] ;
                                       'RunbookName' = $Schedules."$scheduleName".RunbookName ;
                                       'Parameter' = $Schedules."$scheduleName".Parameter}
    }
    return $returnObj
}
Function Set-SmaRepositoryInformationCommitVersion
{
    Param([Parameter(Mandatory=$false)][string] $RepositoryInformation,
          [Parameter(Mandatory=$false)][string] $Path,
          [Parameter(Mandatory=$false)][string] $Commit)

    
    $RepositoryInformation = (ConvertFrom-JSON $RepositoryInformation)
    $RepositoryInformation."$Path".CurrentCommit = $Commit

    return (ConvertTo-Json $RepositoryInformation)
}
Export-ModuleMember -Function * -Verbose:$false -Debug:$False