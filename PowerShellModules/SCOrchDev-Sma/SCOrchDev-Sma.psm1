$LocalAutomationVariableEndpoints = @('https://localhost', 'http://localhost', 'localhost')
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
    # We can't call Get-AutomationVariable in SMA from a function, so we have to determine if we
    # are developing locally. If we are, we can call Get-AutomationVariable. If not, we'll call
    # Get-SMAVariable and pass it an endpoint representing localhost.
    If((Test-LocalDevelopment) -and ($WebServiceEndpoint -in (Get-LocalAutomationVariableEndpoint)))
    {
        # Note that even though it looks like we should be getting variables from the local development
        # system, there is a chance we won't be.
        #
        # Get-AutomationVariable contains logic that may call Get-SMAVariable - this allows for getting
        # variables from real SMA during local testing or troubleshooting scenarios.
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

    Return (Get-BatchSMAVariable -Prefix $Prefix -Name $Name -WebServiceEndpoint (Get-LocalAutomationVariableEndpoint)[0])
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

<#
.SYNOPSIS
    Returns a list of web service endpoints which represent the local system.
#>
function Get-LocalAutomationVariableEndpoint
{
    # We need this function to expose the list of endpoints to the LocalDev module.
    return $LocalAutomationVariableEndpoints
}
Export-ModuleMember -Function * -Verbose:$false