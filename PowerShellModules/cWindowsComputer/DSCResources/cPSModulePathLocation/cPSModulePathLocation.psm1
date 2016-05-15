function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [parameter(Mandatory = $true)]
        [System.String[]]
        $Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Present','Absent')]
        [System.String]
        $Ensure
    )

    $Ensure = 'Present'
    Foreach($_Path in $Path)
    {
        $_Path1 = ";$($_Path);"
        $_Path2 = ";$($_Path)"
        $_Path3 = "$($_Path);"
        if($env:PSModulePath -notlike "*$_Path1*")
        {
            if($env:PSModulePath  -notlike "*$($_Path2)")
            {
                if($env:PSModulePath  -notlike "$($_Path3)*")
                {
                    $Ensure = 'Absent'
                    break
                }
            }
        }
    }

    $returnValue = @{
		Name = $Name
        Path = $PSModulePath
        Ensure = $Ensure
	}

	$returnValue
}


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [parameter(Mandatory = $true)]
        [System.String[]]
        $Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Present','Absent')]
        [System.String]
        $Ensure
    )

    foreach($_Path in $Path)
    {
        $_Path1 = ";$($_Path);"
        $_Path2 = ";$($_Path)"
        $_Path3 = "$($_Path);"
        if($Ensure -eq 'Present')
        {
            if($env:PSModulePath  -notlike "*$_Path1*")
            {
                if($env:PSModulePath  -notlike "*$($_Path2)")
                {
                    if($env:PSModulePath  -notlike "$($_Path3)*")
                    {
                        $env:PSModulePath = "$env:PSModulePath;$($_Path)"
                    }
                }
            }
        }
        else
        {
            if($env:PSModulePath -like "*$_Path1*")
            {
                $env:PSModulePath = $env:PSModulePath.Replace($_Path1,';')
            }
            elseif($env:PSModulePath -like "*$($_Path2)")
            {
                $env:PSModulePath = $env:PSModulePath.Replace($_Path2,'')
            }
            elseif($env:PSModulePath -like "$($_Path3)*")
            {
                $env:PSModulePath = $env:PSModulePath.Replace($_Path3,'')
            }
            
        }
    }
    
    [System.Environment]::SetEnvironmentVariable("PSModulePath", $env:PSModulePath, [System.EnvironmentVariableTarget]::Machine)
    $global:DSCMachineStatus = 1
}


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [parameter(Mandatory = $true)]
        [System.String[]]
        $Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Present','Absent')]
        [System.String]
        $Ensure
    )

    $returnValue = Get-TargetResource -Name $Name -Path $Path -Ensure $Ensure
    Return ($returnValue.Ensure -eq $Ensure) -as [bool]
}


Export-ModuleMember -Function *-TargetResource

