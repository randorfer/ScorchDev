<#
    .SYNOPSIS
       Invokes an integration test
#>
Param(
    $Path,
    $Recipient
)
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$CompletedParameters = Write-StartingMessage

$Vars = Get-BatchAutomationVariable -Name  'From', 'SmtpServer' `
                                    -Prefix 'ContinuousIntegration'

$Credential = Get-AutomationPSCredential -Name $Vars.DomainCredentialName

Try
{
    $Results = Invoke-IntegrationTest -Path $Path
    $TempDirectory = New-TempDirectory
    $ResultFile = "$TempDirectory\Results.txt"
    $Results | ConvertTo-Json -Depth ([int]::MaxValue) > $ResultFile
    Send-MailMessage -To $Recipient `
                     -Attachments $ResultFile `
                     -SmtpServer $Vars.SmtpServer `
                     -Subject 'Integration Test Result' `
                     -From $Vars.From
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
