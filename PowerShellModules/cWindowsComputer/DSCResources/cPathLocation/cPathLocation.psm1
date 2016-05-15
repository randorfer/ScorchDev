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
        if($env:PATH -notlike "*$_Path1*")
        {
            if($env:PATH -notlike "*$($_Path2)")
            {
                if($env:PATH -notlike "$($_Path3)*")
                {
                    $Ensure = 'Absent'
                    break
                }
            }
        }
    }

    $returnValue = @{
		Name = $Name
        Path = $env:PATH
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
            if($env:PATH -notlike "*$_Path1*")
            {
                if($env:PATH -notlike "*$($_Path2)")
                {
                    if($env:PATH -notlike "$($_Path3)*")
                    {
                        $env:PATH = "$env:PATH;$($_Path)"
                    }
                }
            }
        }
        else
        {
            if($env:PATH -like "*$_Path1*")
            {
                $env:Path = $env:Path.Replace($_Path1,';')
            }
            elseif($env:PATH -like "*$($_Path2)")
            {
                $env:Path = $env:Path.Replace($_Path2,'')
            }
            elseif($env:PATH -like "$($_Path3)*")
            {
                $env:Path = $env:Path.Replace($_Path3,'')
            }
            
        }
    }
    
    [System.Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)
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

