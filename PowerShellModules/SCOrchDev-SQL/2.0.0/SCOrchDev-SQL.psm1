#requires -Version 2
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
        [Parameter(Mandatory = $True)]
        [string]
        $query,
        
        [Parameter(Mandatory = $False)]
        [System.Collections.Hashtable]
        $parameters,
        
        [Parameter(Mandatory = $True)]
        [string]
        $connectionString, 
        
        [Parameter(Mandatory = $False)]
        [int]
        $timeout = 60
    )
    # convert parameter string to array of SqlParameters
    try
    {
        Write-Debug -Message "`$query [$query]"
        Write-Debug -Message "`$connectionString [$connectionString]"
        Write-Debug -Message "`$timeout [$timeout]"
        foreach($paramKey in $parameters.Keys)
        {
            Write-Debug -Message "`$paramKey   [$paramKey]"
            Write-Debug -Message "`$ParamValue [$($parameters[$paramKey])]"
        }
        $sqlConnection = New-Object -TypeName System.Data.SqlClient.SqlConnection -ArgumentList $connectionString
        $sqlConnection.Open()

        #Create a command object
        $sqlCommand = $sqlConnection.CreateCommand()
        $sqlCommand.CommandText = $query
        if($parameters)
        {
            foreach($key in $parameters.Keys)
            {
                $null = $sqlCommand.Parameters.AddWithValue($key, $parameters[$key])
            }
        }

        $sqlCommand.CommandTimeout = $timeout

        #Execute the Command
        $sqlReader = $sqlCommand.ExecuteReader()

        $Datatable = New-Object -TypeName System.Data.DataTable
        $Datatable.Load($sqlReader)


        return $Datatable
    }
    finally
    {
        if($sqlConnection -and $sqlConnection.State -ne [System.Data.ConnectionState]::Closed)
        {
            $sqlConnection.Close()
        }
    }
}
Export-ModuleMember -Function * -Verbose:$False
