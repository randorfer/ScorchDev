Configuration AzureAutomation
{
    Param(
    )

    #Import the required DSC Resources
    Import-DscResource -Module xPSDesiredStateConfiguration
    Import-DscResource -Module PSDesiredStateConfiguration
    Import-DscResource -Module cGit -ModuleVersion 0.1.3
    Import-DscResource -Module cWindowscomputer
    Import-DscResource -Module cAzureAutomation

    $SourceDir = 'c:\Source'

    $Vars = Get-BatchAutomationVariable -Prefix 'AzureAutomation' -Name @(
        'WorkspaceID',
        'AutomationAccountURL',
        'AutomationAccountPrimaryKeyName',
        'HybridRunbookWorkerGroupName',
        'GitRepository',
        'LocalGitRepositoryRoot'
    )
    
    $WorkspaceCredential = Get-AutomationPSCredential -Name $Vars.WorkspaceID
    $WorkspaceKey = $WorkspaceCredential.GetNetworkCredential().Password

    $PrimaryKeyCredential = Get-AutomationPSCredential -Name $Vars.AutomationAccountPrimaryKeyName
    $PrimaryKey = $PrimaryKeyCredential.GetNetworkCredential().Password

    $MMARemotSetupExeURI = 'https://go.microsoft.com/fwlink/?LinkID=517476'
    $MMASetupExe = 'MMASetup-AMD64.exe'
    
    $MMACommandLineArguments = 
        '/Q /C:"setup.exe /qn ADD_OPINSIGHTS_WORKSPACE=1 AcceptEndUserLicenseAgreement=1 ' +
        "OPINSIGHTS_WORKSPACE_ID=$($Vars.WorkspaceID) " +
        "OPINSIGHTS_WORKSPACE_KEY=$($WorkspaceKey)`""

    $GITVersion = '2.8.1'
    $GITRemotSetupExeURI = "https://github.com/git-for-windows/git/releases/download/v$($GITVersion).windows.1/Git-$($GITVersion)-64-bit.exe"
    $GITSetupExe = "Git-$($GITVersion)-64-bit.exe"
    
    $GITCommandLineArguments = 
        '/VERYSILENT /NORESTART /NOCANCEL /SP- ' +
        '/COMPONENTS="icons,icons\quicklaunch,ext,ext\shellhere,ext\guihere,assoc,assoc_sh" /LOG'

    Node HybridRunbookWorker
    {
        File SourceFolder
        {
            DestinationPath = $($SourceDir)
            Type = 'Directory'
            Ensure = 'Present'
        }
        xRemoteFile DownloadGitSetup
        {
            Uri = $GITRemotSetupExeURI
            DestinationPath = "$($SourceDir)\$($GITSetupExe)"
            MatchSource = $False
            DependsOn = '[File]SourceFolder'
        }
        xPackage InstallGIT
        {
             Name = "Git version $($GITVersion)"
             Path = "$($SourceDir)\$($GitSetupExE)" 
             Arguments = $GITCommandLineArguments 
             Ensure = 'Present'
             InstalledCheckRegKey = 'SOFTWARE\GitForWindows'
             InstalledCheckRegValueName = 'CurrentVersion'
             InstalledCheckRegValueData = $GITVersion
             ProductID = ''
             DependsOn = "[xRemoteFile]DownloadGitSetup"
        }
        $HybridRunbookWorkerDependency = @('[xPackage]InstallGIT')

        cPathLocation GitExePath
        {
            Name = 'GitEXEPath'
            Path = @(
                'C:\Program Files\Git\cmd'
            )
            Ensure = 'Present'
            DependsOn = '[xPackage]InstallGIT'
        }
        $HybridRunbookWorkerDependency = @("[xPackage]InstallGIT")

        File LocalGitRepositoryRoot
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = $Vars.LocalGitRepositoryRoot
            DependsOn = '[xPackage]InstallGIT'
        }
        
        $RepositoryTable = $Vars.GitRepository | ConvertFrom-JSON | ConvertFrom-PSCustomObject
        
        $PSModulePath = @()
        Foreach ($RepositoryPath in $RepositoryTable.Keys)
        {
            $RepositoryName = $RepositoryPath.Split('/')[-1]
            $Branch = $RepositoryTable.$RepositoryPath
            $PSModulePath += "$($Vars.LocalGitRepositoryRoot)\$($RepositoryName)\PowerShellModules"
            cGitRepository "$RepositoryName"
            {
                Repository = $RepositoryPath
                BaseDirectory = $Vars.LocalGitRepositoryRoot
                Ensure = 'Present'
                DependsOn = '[xPackage]InstallGIT'
            }
            $HybridRunbookWorkerDependency += "[cGitRepository]$($RepositoryName)"
            
            cGitRepositoryBranch "$RepositoryName-$Branch"
            {
                Repository = $RepositoryPath
                BaseDirectory = $Vars.LocalGitRepositoryRoot
                Branch = $Branch
                DependsOn = '[xPackage]InstallGIT'
            }
            $HybridRunbookWorkerDependency += "[cGitRepositoryBranch]$RepositoryName-$Branch"
            
            cGitRepositoryBranchUpdate "$RepositoryName-$Branch"
            {
                Repository = $RepositoryPath
                BaseDirectory = $Vars.LocalGitRepositoryRoot
                Branch = $Branch
                DependsOn = '[xPackage]InstallGIT'
            }
            $HybridRunbookWorkerDependency += "[cGitRepositoryBranchUpdate]$RepositoryName-$Branch"
        }
        
        cPSModulePathLocation GITRepositoryPowerShellModules
        {
            Name = 'GITRepositoryPowerShellModules'
            Path = $PSModulePath
            Ensure = 'Present'
            DependsOn = '[File]LocalGitRepositoryRoot'
        }

        xRemoteFile DownloadMicrosoftManagementAgent
        {
            Uri = $MMARemotSetupExeURI
            DestinationPath = "$($SourceDir)\$($MMASetupExe)"
            MatchSource = $False
        }
        Package InstallMicrosoftManagementAgent
        {
             Name = 'Microsoft Monitoring Agent' 
             ProductId = 'E854571C-3C01-4128-99B8-52512F44E5E9'
             Path = "$($SourceDir)\$($MMASetupExE)" 
             Arguments = $MMACommandLineArguments 
             Ensure = 'Present'
             DependsOn = "[xRemoteFile]DownloadMicrosoftManagementAgent"
        }
        $HybridRunbookWorkerDependency += "[Package]InstallMicrosoftManagementAgent"

        cHybridRunbookWorkerRegistration HybridRegistration
        {
            RunbookWorkerGroup = $Vars.HybridRunbookWorkerGroupName
            AutomationAccountURL = $Vars.AutomationAccountURL
            Key = $PrimaryKey
            DependsOn = $HybridRunbookWorkerDependency
        }
    }
}
