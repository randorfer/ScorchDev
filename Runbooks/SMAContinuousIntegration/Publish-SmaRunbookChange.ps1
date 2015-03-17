<#
    .Synopsis
        Takes a ps1 file and publishes it to the current SMA environment.
    
    .Parameter FilePath
        The full path to the script file

    .Parameter CurrentCommit
        The current commit to store this version under

    .Parameter RepositoryName
        The name of the repository that will be listed as the 'owner' of this
        runbook
#>
Workflow Publish-SMARunbookChange
{
    Param(
        [Parameter(Mandatory=$True)]
        [String]
        $FilePath,

        [Parameter(Mandatory=$True)]
        [String]
        $CurrentCommit,

        [Parameter(Mandatory=$True)]
        [String]
        $RepositoryName
    )
    
    Write-Verbose -Message "[$FilePath] Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

    Try
    {
        $WorkflowName = Get-SmaWorkflowNameFromFile -FilePath $FilePath
        
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        $Runbook = Get-SmaRunbook -Name $WorkflowName `
                                  -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                  -Port $CIVariables.WebservicePort `
                                  -Credential $SMACred
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        if(Test-IsNullOrEmpty $Runbook.RunbookID.Guid)
        {
            Write-Verbose -Message "[$WorkflowName] Initial Import"
            
            $ImportedRunbook = Import-SmaRunbook -Path $FilePath `
                                                 -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                 -Port $CIVariables.WebservicePort `
                                                 -Credential $SMACred
            
            $Runbook = Get-SmaRunbook -Name $WorkflowName `
                                      -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                      -Port $CIVariables.WebservicePort `
                                      -Credential $SMACred
            $TagLine = "RepositoryName:$RepositoryName;CurrentCommit:$CurrentCommit;"
            $NewVersion = $True
        }
        else
        {
            Write-Verbose -Message "[$WorkflowName] Update"
            $TagUpdateJSON = New-SmaChangesetTagLine -TagLine $Runbook.Tags `
                                                     -CurrentCommit $CurrentCommit `
                                                     -RepositoryName $RepositoryName
            $TagUpdate = ConvertFrom-Json $TagUpdateJSON
            $TagLine = $TagUpdate.TagLine
            $NewVersion = $TagUpdate.NewVersion
            if($NewVersion)
            {
                $EditStatus = Edit-SmaRunbook -Overwrite `
                                              -Path $FilePath `
                                              -Name $WorkflowName `
                                              -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                              -Port $CIVariables.WebservicePort `
                                              -Credential $SMACred                
            }
            else
            {
                Write-Verbose -Message "[$WorkflowName] Already is at commit [$CurrentCommit]"
            }
        }
        if($NewVersion)
        {
            $PublishHolder = Publish-SmaRunbook -Name $WorkflowName `
                                                -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                -Port $CIVariables.WebservicePort `
                                                -Credential $SMACred

            Set-SmaRunbookTags -RunbookID $Runbook.RunbookID.Guid `
                               -Tags $TagLine `
                               -WebserviceEndpoint $CIVariables.WebserviceEndpoint `
                               -Port $CIVariables.WebservicePort `
                               -Credential $SMACred
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "[$FilePath] Finished [$WorkflowCommandName]"
}

# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUZvkM2A52DoGtfj5E6WJEkkIP
# A5GgggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
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
# FgQUexxyyveURkFkqeKpHOFPfEdUz/MwDQYJKoZIhvcNAQEBBQAEgYA0v3CS0fpp
# Hn9hibofm/tXM1nP0YtAITbT/Ug278y7Y8xP+Bz9WcnLuCX9Np97ZyHMmWeKa+zm
# O0ysJJ5iNsHvszkE7gdsc2KHToXOmHfiEfoQZwm67wmSjBp6VDzzcZUPx4MGfkxF
# 6buX1iBCfwQjvx2//bSIue6JaRWs07ysIw==
# SIG # End signature block
