param (
    [string]$DatabaseName
)

$server = "localhost"
$user = "sa"
$password = "P@ssword"

# Step 1: Drop existing procedure if it exists
$dropProc = @"
IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND name = 'UpdateCustomerBalances$DatabaseName')
BEGIN
    DROP PROCEDURE dbo.UpdateCustomerBalances$DatabaseName;
END
"@

Invoke-Sqlcmd -Query $dropProc -ServerInstance $server -Username $user -Password $password -Database $DatabaseName

# Step 2: Define the CREATE PROCEDURE body
$createProc = @"
CREATE PROCEDURE dbo.UpdateCustomerBalances$DatabaseName
    @commitCount INT = 100
AS
BEGIN
    SET NOCOUNT ON;   
    DECLARE @minrow INT = 0;
    DECLARE @randPct FLOAT = 0;
    DECLARE @maxRows INT = 1490000;
    DECLARE @selectRows INT = 10000;
    DECLARE @amount FLOAT = 0.0;
    DECLARE @i INT = 0;

    WHILE @i < @commitCount
    BEGIN
        SET @i = @i + 1;
        SET @randPct = ROUND(100 * RAND(), 1);
        SET @minrow = CAST(@maxRows * @randPct / 100 AS INT);
        SET @amount = 200 * (RAND() - 0.5);

        BEGIN TRANSACTION
            UPDATE [$DatabaseName].[dbo].[customer]
            SET [c_acctbal] = [c_acctbal] + @amount
            WHERE [c_custkey] >= @minrow AND [c_custkey] < @minrow + @selectRows;
        COMMIT TRANSACTION;

        -- Optional: Comment these if you don't want verbose DBCC output
        BEGIN TRY
            DBCC FREEPROCCACHE WITH NO_INFOMSGS;
            DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS;
        END TRY
        BEGIN CATCH
            -- Ignore errors silently or log them
        END CATCH

        PRINT CONCAT('Iteration ', @i, ' updating from row ', @minrow);
    END
END;
"@

Invoke-Sqlcmd -Query $createProc -ServerInstance $server -Username $user -Password $password -Database $DatabaseName