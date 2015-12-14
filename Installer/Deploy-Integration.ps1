Param(
    [Parameter(
        Mandatory = $True
    )]
    [String]
    $Path,

    [Parameter(
        Mandatory = $True
    )]
    [String]
    $RepositoryName
)
    
$CompletedParams = Write-StartingMessage -CommandName 'Deploy Integration'
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

$CurrentCommit = Get-GitCurrentCommit -Path $Path

Foreach($RunbookFile in (Get-ChildItem -Path "$($Path)\Runbooks" -Recurse -Filter *.ps1))
{
    Publish-SMARunbookChange -FilePath $RunbookFile.FullName -CurrentCommit $CurrentCommit -RepositoryName $RepositoryName
}
Foreach($SettingsFile in (Get-ChildItem -Path "$($Path)\Globals" -Recurse -Filter *.json))
{
    Publish-SMASettingsFileChange -FilePath $SettingsFile.FullName -CurrentCommit $CurrentCommit -RepositoryName $RepositoryName
}
Write-CompletedMessage @CompletedParams