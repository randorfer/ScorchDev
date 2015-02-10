<#
	Some Stuff
#>
Workflow Start-SmaRunbookListRepublish
{
    Param([array]  $RunbookList,
          [string] $WebServiceEndpoint = "https://localhost")
    
    $CredName = (Get-SmaVariable -Name "SMAContinuousIntegration-CredName" -WebServiceEndpoint $WebServiceEndpoint).Value
	Write-Verbose -Message "Accessing Credential Store for Cred $CredName"
	$cred = Get-AutomationPSCredential -Name $CredName
    
    $needToRepublish = $false
    ForEach -Parallel ($RunbookName in $RunbookList)
    {
        $RunbookDefinition = Get-SmaRunbookDefinition -Name $RunbookName `
                                                      -Type Published `
                                                      -WebServiceEndpoint $WebServiceEndpoint `
                                                      -Credential $cred
        
        if($RunbookDefinition.RunbookVersion.VersionNumber -le 2)
        {
            $Workflow:needToRepublish = $true
        }
    }
    
    if($needToRepublish)
    {
        $DirectoryExists = $true
        while($DirectoryExists)
        {
            $tempDirectory   = "C:\temp\$([System.Guid]::NewGuid())"
            $DirectoryExists = Test-Path $tempDirectory
        }

        $DirObj = inlinescript 
        { 
            $tempDirectory = $Using:tempDirectory
            New-Item -ItemType Directory -Path $tempDirectory -Force -Confirm:$false 
        }

        ForEach -Parallel ($RunbookName in $RunbookList)
        {
            $RunbookInstance = Get-SmaRunbook -Name $RunbookName `
                                              -WebServiceEndpoint $WebServiceEndpoint `
                                              -Credential $cred

            $RunbookDefinition = Get-SmaRunbookDefinition -VersionId $RunbookInstance.PublishedRunbookVersionID `
                                                          -WebServiceEndpoint $WebServiceEndpoint `
                                                          -Credential $cred

            $RunbookFile = inlinescript
            {
                $tempDirectory     = $using:tempDirectory
                $RunbookName       = $using:RunbookName
                $RunbookDefinition = $using:RunbookDefinition

                New-Item -ItemType File `
                         -Path "$($tempDirectory)\$RunbookName.ps1" `
                         -Value $RunbookDefinition.Content `
                         -Force
            }
        
            Edit-SmaRunbook -Name $RunbookName `
                            -WebServiceEndpoint $WebServiceEndpoint `
                            -Credential $cred `
                            -Path $Runbookfile.FullName `
                            -Overwrite

            $publishId = Publish-SmaRunbook -Name $RunbookName `
                                            -WebServiceEndpoint $WebServiceEndpoint `
                                            -Credential $cred `
                                            -Confirm:$false
        
            inlinescript 
            {
                $RunbookFile = $Using:RunbookFile
                Remove-Item -Path $RunbookFile.FullName `
                            -Force
            }
        }

        inlinescript 
        { 
            $tempDirectory = $Using:tempDirectory
            Remove-Item -Path $tempDirectory `
                        -Force 
        }
    }
}