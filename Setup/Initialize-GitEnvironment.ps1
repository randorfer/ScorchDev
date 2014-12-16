Workflow Initialize-GitEnvironment
{
    if([System.Environment]::Is64BitOperatingSystem) { $GitPath = 'C:\Program Files (x86)\Git\bin\git.exe' }
    else                                             { $GitPath = 'C:\Program Files\Git\bin\git.exe' }
    
    if(-not (Test-Path -Path $GitPath))
    {
        Write-Verbose "Installing Git"
        # if Git isn't setup download and install Git for windows from http://msysgit.github.io/
        inlinescript
        {
            $GitPath = $Using:GitPath
            $GitSource  = 'https://github.com/msysgit/msysgit/releases/download'
            $GitVersion = 'Git-1.9.4-preview20140929'
            $GitInstall = "$([IO.Path]::GetTempPath())\$GitVersion.exe"
            (new-object Net.WebClient).DownloadFile("$GitSource/$GitVersion/$GitVersion.exe", $GitInstall)
            & $GitInstall /VERYSILENT /SUPPRESSMSGBOXES
            
            $CurrentValue = [Environment]::GetEnvironmentVariable("Path", "Machine")
            if($CurrentValue -notcontains $(([System.IO.FileInfo]$Gitpath).DirectoryName))
            {
                [Environment]::SetEnvironmentVariable("Path", $CurrentValue + ";$(([System.IO.FileInfo]$Gitpath).DirectoryName)", "Machine")
            }
        }
    }
    else
    {
        Write-Verbose "Git is already installed"
    }
    Checkpoint-Workflow

    if(-not (Get-Module -ListAvailable | ? { $_.Name -eq 'PsGet' }))
    {
        Write-Verbose -Message "Installing PsGet"
        inlinescript { $ErrorActionPreference = 'SilentlyContinue'; (new-object Net.WebClient).DownloadString("http://psget.net/GetPsGet.ps1") | iex }
    }
    else
    {
        Write-Verbose -Message "PsGet already installed"
    }
    Checkpoint-Workflow

    if(-not (Get-Module -ListAvailable | ? { $_.Name -eq 'Posh-Git' }))
    {
        Write-Verbose -Message "Intalling Posh-Git"
        inlinescript { $ErrorActionPreference = 'SilentlyContinue'; Install-Module posh-git }
    }
    else
    {
        Write-Verbose "Posh-Git already installed"
    }
}