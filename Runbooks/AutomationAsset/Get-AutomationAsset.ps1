# http://blogs.technet.com/b/orchestrator/archive/2014/03/27/authoring-sma-runbooks-in-the-powershell-ise.aspx
# http://gallery.technet.microsoft.com/Service-Management-d4edfbf4

workflow Get-AutomationAsset {
    param(
        [Parameter(Mandatory=$True)]
        [ValidateSet('Variable','Certificate','PSCredential', 'Connection')]
        [string] $Type,

        [Parameter(Mandatory=$True)]
        [string]$Name
    )

    $Val = $null

    # Get asset
    if($Type -eq "Variable") {
        $Val = Get-AutomationVariable -Name $Name
    }
    elseif($Type -eq "Certificate") {
        $Temp = Get-AutomationCertificate -Name $Name

        if($Temp) {
            $Val = $Temp.Thumbprint
        }
    }
    elseif($Type -eq "Connection") {
        $Val = Get-AutomationConnection -Name $Name
    }
    elseif($Type -eq "PSCredential") {
        $Temp = Get-AutomationPSCredential -Name $Name

        if($Temp) {
            $Val = @{
                "Username" = $Temp.Username;
                "Password" = $Temp.GetNetworkCredential().Password
            }
        }
    }

    if(!$Val) {
        throw "Automation asset '$Name' of type $Type does not exist in SMA"
    }
    else {
        # Serialize asset value as xml and then return it
        $SerializedOutput = [System.Management.Automation.PSSerializer]::Serialize($Val)

        $SerializedOutput
    }
}