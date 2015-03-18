<# 
.Synopsis
    Uses ADO .NET to query SQL

.Description
    Queries a SQL Database and returns a datatable of results

.Parameter query
    The SQL Query to run
 
.Parameter parameters
    A list of SQLParameters to pass to the query

.Parameter connectionString
    Sql Connection string for the DB to connect to

.Parameter timeout
    timeout property for SQL query. Default is 60 seconds

.Example
   # run a simple query

   $connectionString = ""
   $parameters = @{}
   Invoke-SqlQuery -query "SELECT GroupID, GroupName From [dbo].[Group] WHERE GroupName=@GroupName" -parameters @{"@GroupName"="genmills\groupName"} -connectionString $connectionString;
   Invoke-SqlQuery -query "SELECT GroupID, GroupName From [dbo].[Group]" -parameters @{} -connectionString $connectionString;
   
#>
function Invoke-SqlQuery
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]
        $query,
        
        [Parameter(Mandatory=$False)]
        [System.Collections.Hashtable]
        $parameters,
        
        [Parameter(Mandatory=$True)]
        [string]
        $connectionString, 
        
        [Parameter(Mandatory=$False)]
        [int]
        $timeout=60
    )
    # convert parameter string to array of SqlParameters
    try
    {
		Write-Verbose -Message "`$query [$query]"
		Write-Verbose -Message "`$connectionString [$connectionString]"
		Write-Verbose -Message "`$timeout [$timeout]"
		foreach($paramKey in $parameters.Keys)
		{
			Write-Verbose -Message "`$paramKey   [$paramKey]"
			Write-Verbose -Message "`$ParamValue [$($parameters[$paramkey])]"
		}
        $sqlConnection = new-object System.Data.SqlClient.SqlConnection $connectionString
        $sqlConnection.Open()

        #Create a command object
        $sqlCommand = $sqlConnection.CreateCommand()
        $sqlCommand.CommandText = $query;
        if($parameters)
        {
            foreach($key in $parameters.Keys)
            {
                $sqlCommand.Parameters.AddWithValue($key, $parameters[$key]) | Out-Null
            }
        }
		
		$sqlCommand.CommandTimeout = $timeout

        #Execute the Command
        $sqlReader = $sqlCommand.ExecuteReader()

        $Datatable = New-Object System.Data.DataTable
        $DataTable.Load($SqlReader)


        return $DataTable;
    }
    finally
    {
        if($sqlConnection -and $sqlConnection.State -ne [System.Data.ConnectionState]::Closed)
        {
            $sqlConnection.Close();
        }
    }
}
Export-ModuleMember -Function * -Verbose:$false
# SIG # Begin signature block
# MIID1QYJKoZIhvcNAQcCoIIDxjCCA8ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUz30B3P1oHKzRHFSpUB6ew8xm
# S2WgggH3MIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
# AQUFADAUMRIwEAYDVQQDDAlTQ09yY2hEZXYwHhcNMTUwMzA5MTQxOTIxWhcNMTkw
# MzA5MDAwMDAwWjAUMRIwEAYDVQQDDAlTQ09yY2hEZXYwgZ8wDQYJKoZIhvcNAQEB
# BQADgY0AMIGJAoGBANbZ1OGvnyPKFcCw7nDfRgAxgMXt4YPxpX/3rNVR9++v9rAi
# pY8Btj4pW9uavnDgHdBckD6HBmFCLA90TefpKYWarmlwHHMZsNKiCqiNvazhBm6T
# XyB9oyPVXLDSdid4Bcp9Z6fZIjqyHpDV2vas11hMdURzyMJZj+ibqBWc3dAZAgMB
# AAGjRjBEMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBQ75WLz6WgzJ8GD
# ty2pMj8+MRAFTTAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQEFBQADgYEAoK7K
# SmNLQ++VkzdvS8Vp5JcpUi0GsfEX2AGWZ/NTxnMpyYmwEkzxAveH1jVHgk7zqglS
# OfwX2eiu0gvxz3mz9Vh55XuVJbODMfxYXuwjMjBV89jL0vE/YgbRAcU05HaWQu2z
# nkvaq1yD5SJIRBooP7KkC/zCfCWRTnXKWVTw7hwxggFIMIIBRAIBATAoMBQxEjAQ
# BgNVBAMMCVNDT3JjaERldgIQEdV66iePd65C1wmJ28XdGTAJBgUrDgMCGgUAoHgw
# GAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGC
# NwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQx
# FgQUBKqslQKf9Z9rZGNBDFMfOl4/5RMwDQYJKoZIhvcNAQEBBQAEgYDNPY9X972v
# UH+SdI2p/mE21SynO+orwN8GWGRBzv6CR2J2hw7DWJTq1H75Oj5BPnnkAT2Ixzsx
# /1ERR4pWhz+SJa8DIdmTAgqdtbxpajoLB7g5kh/7YA+Z7Gsvq+HmvdlI3uoAibsz
# kwJO1Mat70QJy2bCjTO0fbWPB1oQr1vDDg==
# SIG # End signature block
