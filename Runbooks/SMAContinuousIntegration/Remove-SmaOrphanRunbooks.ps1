Workflow Remove-SmaOrphanRunbooks
{
    Param($TFSServer,
          $TFSCollection,
          $SourcePath,
          $Branch,
          $WebServiceEndpoint = "https://localhost")

    Function Get-TFSStoredRunbooks
    {
        Param($TFSServer, $TFSCollection, $SourcePath, $Branch)

        Write-Verbose -Message "Beginning Get-TFSStoredRunbooks"
        # Build the TFS Location (server and collection)
        $TFSServerCollection = $TFSServer + "\" + $TFSCollection
        
        Write-Verbose -Message "Searching TFS Workspace [$($TFSServerCollection)] for all Referenced Runbooks"
        # Load the necessary assemblies for interacting with TFS
        $VClient  = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.VersionControl.Client")
        $TFClient = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.Client")
    
        # Connect to TFS
        $regProjCollection = [Microsoft.TeamFoundation.Client.RegisteredTfsConnections]::GetProjectCollection($TFSServerCollection)
    
        # This is necessary to interact with your TFS from a source control perspective
        $tfsTeamProjCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($regProjCollection)
        $vcs = $tfsTeamProjCollection.GetService([Type]"Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer")
        
        $allItems = $vcs.GetItems($SourcePath,2)
        
        foreach ($item in $allItems.Items)
        {
            if($item.ItemType.ToString().Equals('File')) 
            { 
                if($item.ServerItem.ToString().ToLower().EndsWith('.ps1'))
                {
                    $ServerPath = $item.ServerItem.ToString()
                    $fi = Get-Item -Path (($ServerPath.Replace($allItems.QueryPath, $SourcePath)).Replace('/','\'))
                    
                    if($fi.Directory.Name.ToLower().Equals($Branch.ToLower()))
                    {
                        $scriptText = Get-Content -Path $fi.FullName
                        for($i=0; $i -lt $scriptText.Length; $i++)
                        {
                            if($scriptText[$i] -like "workflow*") { $line = $scriptText[$i]; $i = $scriptText.Length } 
                        }

                        $workflowTagFound = $false
                        $runbookName = [System.String]::Empty
                        foreach($str in $line.Split(' '))
                        {
                            if(!$workflowTagFound) { if($str.ToLower().Equals('workflow')) { $workflowTagFound = $true } }
                            else { if($str) { $runbookName = $str; break; } }
                        }
                    
                        $runbookName
                        Write-Verbose -Message "[$($fi.FullName)] [$strValue]"
                    }
                }
            }
        }
        Write-Verbose -Message "Finished Get-TFSStoredRunbooks"
    }

    Function Get-AllSmaRunbooks
    {
        Param(  [Parameter(Mandatory=$true)]  [String]$WebServiceURL,
                [Parameter(Mandatory=$false)] [String]$WebServicePort="9090",
                [Parameter(Mandatory=$false)] [String]$tenantID = "00000000-0000-0000-0000-000000000000",
                [Parameter(Mandatory=$false)] [pscredential] $Credential 
                )

        # Get all versions of the runbook
        $runbooksURI = "$WebServiceURL`:$WebServicePort/$tenantID/Runbooks"
        if ($Credential) { $runbooks = Invoke-RestMethod -Uri $runbooksURI -Credential $Credential }
        else             { $runbooks = Invoke-RestMethod -Uri $runbooksURI -UseDefaultCredentials }

        $addedToBox = $false

        $box = New-Object System.Collections.ArrayList
        foreach ($rB in $runbooks) 
        { 
            $box.Add($rB) | Out-Null
            $addedToBox = $true
        }

        while($addedToBox)
        {
            $addedToBox = $false
            $runbooksURI = "$WebServiceURL`:$WebServicePort/$tenantID/Runbooks?$`skiptoken=guid'$($box[-1].Content.Properties.RunbookID.'#text')'"

            if($credential) { $Runbooks = Invoke-RestMethod -Uri $runbooksURI -Credential $Credential }
            else            { $Runbooks = Invoke-RestMethod -Uri $runbooksURI -UseDefaultCredentials }
                    
            $addedToBox = $false
            foreach ($rB in $Runbooks) 
            { 
                $box.Add($rB) | Out-Null
                $addedToBox = $true
            }
        }
    
        return $box
    }

    $CredName = (Get-SmaVariable -Name "SMAContinuousIntegration-CredName" -WebServiceEndpoint $WebServiceEndpoint).Value
	Write-Verbose -Message "Accessing Credential Store for Cred $CredName"
	$cred = Get-AutomationPSCredential -Name $CredName
    
    $ReferencedWorkflows = Get-TFSStoredRunbooks -TFSServer $TFSServer `
                                                 -SourcePath $SourcePath `
                                                 -TFSCollection $TFSCollection `
                                                 -Branch $Branch

    $SMAWorkflows = Get-AllSmaRunbooks -WebServiceURL $WebServiceEndpoint `
                                       -Credential $cred

    Write-Verbose -Message "Comparing all SMA Workflows to TFS Workflows"
    foreach -Parallel ($SMAWorkflow in $SMAWorkflows)
    {
        inlinescript
        {
            $ReferencedWorkflows = $Using:ReferencedWorkflows
            $SMAWorkflow         = $Using:SMAWorkflow
            $WebServiceEndpoint  = $Using:WebServiceEndpoint
            $Cred                = $Using:Cred

            if(!$ReferencedWorkflows.Contains($SMAWorkflow.content.properties.RunbookName))
            {
                Write-Debug -Message "Removing $($SMAWorkflow.content.properties.RunbookName)"
                Remove-SmaRunbook -Name $SMAWorkflow.content.properties.RunbookName `
                                  -WebServiceEndpoint $WebServiceEndpoint `
                                  -Credential $Cred
				
				New-VariableRunbookTrackingInstance -VariablePrefix 'TFSContinuousIntegration-RemoveOrphanRunbooks' `
	                                                -WebServiceEndpoint $WebServiceEndpoint
            }
        }
    }
    Write-Verbose -Message "Finished comparing all SMA Workflows to TFS Workflows"
}