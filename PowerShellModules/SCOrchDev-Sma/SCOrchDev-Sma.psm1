
<#
.SYNOPSIS
    Gets one or more SMA variable values from the given web service endpoint.

.DESCRIPTION
    Get-BatchSMAVariable gets the value of each SMA variable given in $Name.
    If $Prefix is set, "$Prefix-$Name" is looked up in SMA (helps keep the
    list of variables in $Name concise).

.PARAMETER Name
    A list of variable values to get from SMA.

.PARAMETER WebServiceEndpoint
    The SMA web service endpoint to query for variables.

.PARAMETER Prefix
    A prefix to be applied to each variable name when performing the lookup
    in SMA. A '-' is added to the end of $Prefix automatically.
#>
Function Get-BatchSMAVariable
{
    Param(
        [Parameter(Mandatory=$True)]  [String[]] $Name,
        [Parameter(Mandatory=$True)]  [String]   $WebServiceEndpoint,
        [Parameter(Mandatory=$False)] [AllowNull()] [String] $Prefix = $Null
    )
    $Variables = @{}
    $VarCommand = (Get-Command -Name 'Get-SMAVariable')
    $VarParams = @{'WebServiceEndpoint' = $WebServiceEndpoint}
    # We can't call Get-AutomationVariable in SMA from a function.
    If((Test-LocalDevelopment) -and ($WebServiceEndpoint -in $LocalAutomationVariableEndpoints))
    {
        $VarCommand = (Get-Command -Name 'Get-AutomationVariable')
        $VarParams = @{}
    }
    ForEach($VarName in $Name)
    {
        If(-not [String]::IsNullOrEmpty($Prefix))
        {
            $SMAVarName = "$Prefix-$VarName"
        }
        Else
        {
            $SMAVarName = $VarName
        }
        $Variables[$VarName] = (& $VarCommand -Name "$SMAVarName" @VarParams).Value
        Write-Verbose -Message "Variable [$VarName / $SMAVarName] = [$($Variables[$VarName])]"
    }
    Return (New-Object -TypeName 'PSObject' -Property $Variables)
}

Function Get-BatchAutomationVariable
{
    Param(
        [Parameter(Mandatory=$True)]  $Name,
        [Parameter(Mandatory=$False)] $Prefix = $Null
    )
    Get-BatchSMAVariable -Prefix $Prefix -Name $Name -WebServiceEndpoint $LocalAutomationVariableEndpoints[0]
}

<#
.SYNOPSIS
    Returns $true if working in a development environment outside SMA, $false otherwise.
#>
function Test-LocalDevelopment
{
    $LocalDevModule = Get-Module -ListAvailable -Name 'LocalDev' -Verbose:$False -ErrorAction 'SilentlyContinue' -WarningAction 'SilentlyContinue'
    if($LocalDevModule -ne $null)
    {
        return $true
    }
    return $false
}

Export-ModuleMember -Function *