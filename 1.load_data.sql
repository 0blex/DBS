USE DBSE6
GO

BEGIN 

	DECLARE @base_dir VARCHAR(150) = 'C:\Users\alex.black\Downloads\DBS\'
	DECLARE @file_name VARCHAR(150) 
	DECLARE @path VARCHAR(255)
	DECLARE @SQL NVARCHAR(MAX) 


	-- load ftWetbench
	SET @file_name = 'ftWetbench.csv'

	SET @path = @base_dir + @file_name

	--IF OBJECT_ID('tempdb.dbo.#stg_ftWetbench') IS NOT NULL
	--	DROP TABLE #stg_ftWetbench

	SET @SQL = 'BULK INSERT ftWetbench
						FROM ''' + @path + '''
						WITH (
							FIRSTROW = 2 ,
							FIELDTERMINATOR ='','',
							ROWTERMINATOR =''\n'',
							FORMAT = ''CSV'',
							FIELDQUOTE = ''"''
						)'

	EXEC (@SQL)


	-- load ftWetbenchWO
	SET @file_name = 'ftWetbenchWO.csv'

	SET @path = @base_dir + @file_name

	--IF OBJECT_ID('tempdb.dbo.#stg_ftWetbenchWO') IS NOT NULL
	--	DROP TABLE #stg_ftWetbenchWO

	SET @SQL = 'BULK INSERT ftWetbenchWO
						FROM ''' + @path + '''
						WITH (
							FIRSTROW = 2 ,
							FIELDTERMINATOR ='','',
							ROWTERMINATOR =''\n'',
							FORMAT = ''CSV'',
							FIELDQUOTE = ''"''
						)'

	EXEC (@SQL)


	-- load ftWetbenchWO
	SET @file_name = 'ftWetBenchReportingTimeline.csv'

	SET @path = @base_dir + @file_name

	--IF OBJECT_ID('tempdb.dbo.#stg_ftWetBenchReportingTimeline') IS NOT NULL
	--	DROP TABLE #stg_ftWetBenchReportingTimeline

	SET @SQL = 'BULK INSERT ftWetBenchReportingTimeline
						FROM ''' + @path + '''
						WITH (
							FIRSTROW = 2 ,
							FIELDTERMINATOR ='','',
							ROWTERMINATOR =''\n'',
							FORMAT = ''CSV'',
							FIELDQUOTE = ''"''
						)'

	EXEC (@SQL)

END