<#
    .SYNOPSIS
       Invokes an integration test
#>
Param(
    [object]
    $webhookData
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$CompletedParameters = Write-StartingMessage -CommandName 'Invoke-GitRepositoryIntegrationTest'

$Vars = Get-BatchAutomationVariable -Name  'EmailExchangeVersion', 'EmailWebserviceURL', 'EmailCredentialName', 'RepositoryInformation' `
                                    -Prefix 'ContinuousIntegration'

$EmailCredential = Get-AutomationPSCredential -Name $Vars.EmailCredentialName
Try
{
    $RepositoryInformation = $Vars.RepositoryInformation | ConvertFrom-Json | ConvertFrom-PSCustomObject
    $GithubData = $WebhookData.RequestBody | ConvertFrom-Json
    Foreach($RepositoryName in $RepositoryInformation.Keys)
    {
        $_RepositoryInformation = $RepositoryInformation.$RepositoryName
        if($_RepositoryInformation.RepositoryPath -like "$($GithubData.repository.url)*")
        {
            break
        }
        else
        {
            $_RepositoryInformation = $Null
        }
    }
    if(-not $_RepositoryInformation -as [bool]) 
    { 
        Throw-Exception -Type 'RepositoryNotFound' -Message 'Repository Information not found in Repository Information'
    }
    $BeforeCommit = $GithubData.before
    $AfterCommit = $GithubData.after
    $Recipient = $GithubData.Pusher.Email
    $PathsToCheck = $GithubData.head_commit.added | ForEach-Object { "$($_RepositoryInformation.Path)\$($_.Replace('/','\'))" }
    $PathsToCheck += $GithubData.head_commit.modified | ForEach-Object { "$($_RepositoryInformation.Path)\$($_.Replace('/','\'))" }
    $Result = Invoke-IntegrationTest -Path $PathsToCheck
    
    $EWSConnection = New-EWSMailboxConnection -exchangeVersion $Vars.EmailExchangeVersion `
                                              -Credential $EmailCredential `
                                              -webserviceURL $Vars.EmailWebserviceURL

    Foreach($Key in $Result.Keys)
    {
        Send-EWSEmail -MailboxConnection $EWSConnection `
                      -Recipients $Recipient `
                      -Subject "Integration Test Result [$Key]" `
                      -Body "<a href='$($GithubData.head_commit.url)'>Change</a><br />$($Result.$Key)" `
                      -bodyFormat HTML
    }
}
Catch
{
    $Exception = $_
    $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
    Switch ($ExceptionInfo.FullyQualifiedErrorId)
    {
        Default
        {
            Write-Exception $Exception -Stream Warning
        }
    }
}
Finally
{
    Try { Remove-Item -Path $TempDirectory -Force -Recurse -Confirm:$false }
    Catch { }
}
Write-CompletedMessage @CompletedParameters
