<#
.SYNOPSIS
    Removes old files from the given paths that meet the specified criteria.

.PARAMETER Path
    The paths that should have old files removed from them.

.PARAMETER MaxAgeInDays
    The maximum age of files to keep, in days. Files that have not been modified
    at least this recently will be removed.

.PARAMETER Filter
    A file name filter that limits what files are removed. For example,
    specifying "*.ps1" would remove only files whose extension is ps1.
    By default, there is no filter - all files are subject to deletion.

.PARAMETER Recurse
    If $True, recurse into subdirectories of the provided paths. By default,
    recursion is disabled.

.PARAMETER ComputerName
    The name of the computer to remote to in order to perform deletion. If local
    paths are specified (e.g. C:\Temp), this parameter is mandatory. May also be
    useful to limit bandwidth consumption over WAN links.

.PARAMETER CredentialName
    The name of the SMA credential to use for file deletion.
#>
workflow Remove-OldFile
{
    param(
        [Parameter(Mandatory = $True)]  [String[]] $Path,
        [Parameter(Mandatory = $True)]  [Int] $MaxAgeInDays,
        [Parameter(Mandatory = $False)] [AllowNull()] [String] $Filter,
        [Parameter(Mandatory = $False)] [AllowNull()] [Switch] $Recurse,
        [Parameter(Mandatory = $False)] [AllowNull()] [String] $ComputerName,
        [Parameter(Mandatory = $False)] [AllowNull()] [String] $CredentialName
    )

    if(-not (Test-IsNullOrEmpty -String $CredentialName))
    {
        $Credential = Get-AutomationPSCredential -Name $CredentialName
    }
    else
    {
        $Credential = $null
    }
    $OldFiles = Get-OldFile -Path $Path -MaxAgeInDays $MaxAgeInDays -Filter $Filter `
                            -Recurse:$Recurse -ComputerName $ComputerName -CredentialName $CredentialName
    
    # Checking ($OldFiles -eq $null) here doesn't work, because PowerShell and/or Workflow bug.
    # Sigh...
    if(-not $OldFiles)
    {
        Write-Verbose -Message 'No files to groom'
        return $null
    }
    $SuccessfullyRemovedFiles = InlineScript
    {
        $ComputerName = $Using:ComputerName
        $Credential = $Using:Credential
        $OldFiles = $Using:OldFiles

        $RemotingParameters = Get-OptionalRemotingParameter -ComputerName $ComputerName -Credential $Credential
        # Workflow can't do parameter splatting, so we'll deal with conditional remoting using Invoke-Command
        # inside an InlineScript
        return Invoke-Command @RemotingParameters -ArgumentList $OldFiles -ScriptBlock `
        {
            $OldFiles = $Args
            $SuccessfullyRemovedFiles = New-Object -TypeName 'System.Collections.ArrayList'
            foreach($File in $OldFiles)
            {
                try
                {
                    # We don't have to switch credentials here - remoting will take care of that for us.
                    Remove-Item -LiteralPath $File.FullName -Force -Confirm:$False -ErrorAction 'Stop'
                }
                catch
                {
                    Write-Error -Message "Failed while attempting to remove $($File.FullName)" -ErrorAction 'Continue'
                    Write-Exception -Exception $_ -Stream 'Error'
                    continue
                }
                $SuccessfullyRemovedFiles += $File
            }
            return $SuccessfullyRemovedFiles
        }
    }
    return $SuccessfullyRemovedFiles
}
