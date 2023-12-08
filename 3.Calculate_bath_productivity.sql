USE DBSE6

---- calculate the total quantity, capacity of each run and add in time period ----

IF OBJECT_ID('tempdb.dbo.#RunProductivity') IS NOT NULL
	DROP TABLE #RunProductivity

CREATE TABLE #RunProductivity (
	RunId nvarchar(150),
	EquipmentID varchar(max),
	BathNo int,
	RunNumber int,
	Quantity bigint,
	Productivity float
	);

-- calculate the productivity of individual run
WITH WOProductivity AS (
	SELECT	
		EquipmentID
		,BathNo
		,RunNumber
		,SUM(COALESCE(WWO.WO_Quantity,0)) AS RunQuantity
		,MIN(COALESCE(BathCapacity,0)) AS BathCapacity
	FROM [DBSE6].[dbo].[ftWetbenchWO] WWO
	LEFT JOIN ftBathCapacity BC ON WWO.FixtureType = BC.WOFixture 
					AND WWO.ProductSize = BC.ProductSize
	GROUP BY EquipmentID, BathNo, RunNumber
)

INSERT INTO #RunProductivity (RunId,EquipmentID,BathNo,RunNumber,Quantity,Productivity)
SELECT 
	EquipmentID + ' | ' + CAST(BathNo AS varchar) + ' | ' + CAST(RunNumber as varchar)
	,EquipmentID
	,BathNo
	,RunNumber
	,RunQuantity
	,CASE 
		WHEN BathCapacity <> 0 THEN COALESCE( (CAST(RunQuantity AS FLOAT) / CAST(BathCapacity AS FLOAT)) , 0 ) 
		WHEN BathCapacity = 0 THEN 0
	END AS Productivity
FROM WOProductivity
ORDER BY EquipmentID, BathNo, RunNumber


---- ADD IN THE TIME AND STATUS OF EACH RUN TO THE PRODUCTIVITY ----
IF OBJECT_ID('tempdb.dbo.#RunDetails') IS NOT NULL
	DROP TABLE #RunDetails

CREATE TABLE #RunDetails (
	RunId nvarchar(150),
	EquipmentID varchar(max),
	BathNo int,
	RunNumber int,
	Quantity bigint,
	Productivity float,
	StartTime datetime,
	StopTime datetime,
	[Status] varchar(max)
)


INSERT INTO #RunDetails (RunId,EquipmentID,BathNo,RunNumber,Quantity,Productivity,StartTime,StopTime,[Status])
	SELECT 
		RP.RunId
		,RP.EquipmentID
		,RP.BathNo
		,RP.RunNumber
		,RP.Quantity
		,RP.Productivity
		,T.StartTime
		,T.StopTime
		,T.Status
	FROM #RunProductivity RP
	INNER JOIN (
			SELECT  
				EquipmentID + ' | ' + CAST(BathNo AS varchar) + ' | ' + CAST(RunNumber as varchar) AS RunId
				,StartTime
				,StopTime
				,Status
			FROM ftWetbench
			-- included both Completed and Running statuses 
		) T ON RP.RunId = T.RunId
	WHERE T.StopTime >= T.StartTime -- Remove records were the stop date was before the start date. Impossible record - assumed error, removed from analysis


---- SET UP THE REPORTING PERIODS IN ORDER TO DETERMINE WHICH RUNS FALL WITHIN EACH REPORING PERIOD ----
IF OBJECT_ID('tempdb.dbo.#ReportingPeriod') IS NOT NULL
	DROP TABLE #ReportingPeriod

CREATE Table #ReportingPeriod (
	[PeriodID] nvarchar(50),
	[StartDate] datetime,
	[EndDate] datetime,
	[PeriodMinutes] bigint,
	[Type] nvarchar(50),
	[Year] int,
	[Interval] int,
	[Name] nvarchar(50)
	);


WITH ReportingPeriodDetails AS (
	SELECT
		CASE 
			WHEN [Type] = 'Monthly' THEN 'Month ' + CAST([Interval] AS nvarchar) + ' | ' + CAST([Year] AS nvarchar)
			WHEN [Type] = 'Shiftly' AND CAST([Date] AS TIME) <= '07:00:00' THEN Convert(nvarchar,[Date],102) + ' AM'
			WHEN [Type] = 'Shiftly' AND CAST([Date] AS TIME) > '07:00:00' THEN Convert(nvarchar,[Date],102) + ' PM'
			WHEN [Type] = 'Weekly' THEN TRIM([Name]) + ' | ' + CAST([Year] AS nvarchar)
		END AS PeriodId,
		[Date] AS StartDate,
		LEAD([Date]) OVER ( PARTITION BY [Type] ORDER BY [Date]) AS EndDate,
		[Type],
		[Year],
		[Interval],
		[Name]
	FROM
		ftWetBenchReportingTimeline
)


INSERT INTO #ReportingPeriod ([PeriodID], [StartDate], [EndDate], [PeriodMinutes], [Type], [Year], [Interval], [Name])
	SELECT 
		PeriodId,
		StartDate,
		EndDate,
		DATEDIFF(MINUTE, StartDate, EndDate),
		[Type],
		[Year],
		[Interval],
		[Name]
	FROM ReportingPeriodDetails


---- CALCULATE THE RUNS THAT FALL INTO EACH REPORING PERIOD ----
IF OBJECT_ID('tempdb.dbo.#ReportingPeriodRuns') IS NOT NULL
	DROP TABLE #ReportingPeriodRuns

CREATE TABLE #ReportingPeriodRuns (
	[PeriodID] nvarchar(50),
	[PeriodStartDate] datetime,
	[PeriodEndDate] datetime,
	[PeriodMinutes] bigint,
	[RunId] nvarchar(150),
	[EquipmentID] varchar(max),
	[BathNo] int,
	[RunNumber] int,
	[Quantity] bigint,
	[Productivity] float,
	[RunStartTime] datetime,
	[RunStopTime] datetime,
	[RunMinutes] bigint,
	[Type] varchar(150),
	[ContributingMinutes] bigint,
)


---- ADD ROWS WHERE FULL RUN IS BETWEEN REPORTING START AND END ----
INSERT INTO #ReportingPeriodRuns (PeriodID,PeriodStartDate,PeriodEndDate,PeriodMinutes,
									RunId,EquipmentID,BathNo,RunNumber,Quantity,Productivity,RunStartTime,RunStopTime,RunMinutes,
									[Type],ContributingMinutes)
	SELECT 
		RP.PeriodID
		,RP.StartDate 
		,RP.EndDate 
		,RP.PeriodMinutes
		,RD.RunId
		,RD.EquipmentID
		,RD.BathNo
		,RD.RunNumber
		,RD.Quantity
		,RD.Productivity
		,RD.StartTime 
		,RD.StopTime
		,DATEDIFF(MINUTE, RD.StartTime, RD.StopTime) 
		,'Full Run'
		,DATEDIFF(MINUTE, RD.StartTime, RD.StopTime) -- entire run falls in period so include all minutes
	FROM #ReportingPeriod RP 
	INNER JOIN #RunDetails RD ON (RD.StartTime BETWEEN RP.StartDate AND RP.EndDate) AND (RD.StopTime BETWEEN RP.StartDate AND RP.EndDate)


---- ADD ROWS WHERE RUN WAS PARTIALLY IN REPORTING PERIOD. RUN STARTS IN REPORTING PERIOD----
INSERT INTO #ReportingPeriodRuns (PeriodID,PeriodStartDate,PeriodEndDate,PeriodMinutes,
									RunId,EquipmentID,BathNo,RunNumber,Quantity,Productivity,RunStartTime,RunStopTime,RunMinutes,
									[Type],ContributingMinutes)
	SELECT 
		RP.PeriodID
		,RP.StartDate 
		,RP.EndDate 
		,RP.PeriodMinutes
		,RD.RunId
		,RD.EquipmentID
		,RD.BathNo
		,RD.RunNumber
		,RD.Quantity
		,RD.Productivity
		,RD.StartTime 
		,RD.StopTime
		,DATEDIFF(MINUTE, RD.StartTime, RD.StopTime)
		,'Partial Run. Start in Period'
		,DATEDIFF(MINUTE, RD.StartTime, RP.EndDate) --only contribute time from start of run to end of reporting period
	FROM #ReportingPeriod RP 
	INNER JOIN #RunDetails RD ON (RD.StartTime BETWEEN RP.StartDate AND RP.EndDate) AND (RD.StopTime NOT BETWEEN RP.StartDate AND RP.EndDate)

---- ADD ROWS WHERE RUN WAS PARTIALLY IN REPORTING PERIOD. RUN ENDS IN REPORTING PERIOD----
INSERT INTO #ReportingPeriodRuns (PeriodID,PeriodStartDate,PeriodEndDate,PeriodMinutes,
									RunId,EquipmentID,BathNo,RunNumber,Quantity,Productivity,RunStartTime,RunStopTime,RunMinutes,
									[Type],ContributingMinutes)
	SELECT 
		RP.PeriodID
		,RP.StartDate 
		,RP.EndDate 
		,RP.PeriodMinutes
		,RD.RunId
		,RD.EquipmentID
		,RD.BathNo
		,RD.RunNumber
		,RD.Quantity
		,RD.Productivity
		,RD.StartTime 
		,RD.StopTime
		,DATEDIFF(MINUTE, RD.StartTime, RD.StopTime)
		,'Partial Run. End in Period'
		,DATEDIFF(MINUTE, RP.StartDate, RD.StopTime) --only contribute time from start of reporting period to end of run
	FROM #ReportingPeriod RP 
	INNER JOIN #RunDetails RD ON (RD.StopTime BETWEEN RP.StartDate AND RP.EndDate) AND (RD.StartTime NOT BETWEEN RP.StartDate AND RP.EndDate)


---- ADD IN RUNS WHERE THE RUN PERIOD IS THE ENTIRE REPORTING PERIOD ----
INSERT INTO #ReportingPeriodRuns (PeriodID,PeriodStartDate,PeriodEndDate,PeriodMinutes,
									RunId,EquipmentID,BathNo,RunNumber,Quantity,Productivity,RunStartTime,RunStopTime,RunMinutes,
									[Type],ContributingMinutes)
	SELECT 
		RP.PeriodID
		,RP.StartDate 
		,RP.EndDate 
		,RP.PeriodMinutes
		,RD.RunId
		,RD.EquipmentID
		,RD.BathNo
		,RD.RunNumber
		,RD.Quantity
		,RD.Productivity
		,RD.StartTime 
		,RD.StopTime
		,DATEDIFF(MINUTE, RD.StartTime, RD.StopTime)
		,'Full Reporting Period'
		,DATEDIFF(MINUTE, RP.StartDate, RP.EndDate) --Contribute all minutes of reporting period
	FROM #ReportingPeriod RP 
	INNER JOIN #RunDetails RD ON (RP.StartDate BETWEEN RD.StartTime AND RD.StopTime) AND (RP.EndDate BETWEEN RD.StartTime AND RD.StopTime)

;

---- CALCULATE THE WEIGHTED PRODUCTIVTY OF EACH BENCH AND EACH BATH IN EACH PERIOD
IF OBJECT_ID('tempdb.dbo.#EquipmentProductvity') IS NOT NULL
	DROP TABLE #EquipmentProductvity

CREATE TABLE #EquipmentProductvity (
	[PeriodID] nvarchar(50),
	[EquipmentID] varchar(max),
	[BathNo] int,
	[Quantity] bigint,
	[Productivity] float,
)

; 
WITH RunProductivitySummary AS (
	SELECT 
		RunId
		,EquipmentID
		,BathNo
		,PeriodID
		,productivity
		,Quantity
		,CAST(ContributingMinutes AS float) / CAST(PeriodMinutes AS FLOAT) AS Weighting
		,CAST(ContributingMinutes AS float) / CAST(PeriodMinutes AS FLOAT) * Productivity AS WeightedProductivity
	FROM #ReportingPeriodRuns RPR
	)

INSERT INTO #EquipmentProductvity
	SELECT 
		PeriodID
		,EquipmentID
		,BathNo
		,SUM(Quantity)
		,SUM(WeightedProductivity) 
	FROM RunProductivitySummary
	GROUP BY PeriodID, EquipmentID, BathNo

;
---- THIS QUERY RETURNS THE PRODUCTIVITY FOR EACH BATH IN EACH PERIOD WHERE THERE WAS ACTIVITY IN THAT PERIOD
---- IT EXCLUDES PERIODS WERE NO ACTIVITY WAS RECORDED, FOR EXAMPLE WHERE THE DATA SET STARTED 
WITH AllBathProductivity AS (
	SELECT 
		RP.*
		,EP.EquipmentID
		,EP.BathNo
		,EP.Quantity
		,EP.Productivity
	FROM #ReportingPeriod RP
	INNER JOIN #EquipmentProductvity EP ON RP.PeriodID = EP.PeriodID
) 

SELECT * FROM AllBathProductivity
order by [Type], [Year], [Interval], StartDate, EquipmentID, BathNo

;

---- THE BELOW IS IN AN ADDITION TO THE ABOVE SOLUTION 
---- THIS QUERY IS TO CALCULATE THE PRODUCTIVITY OF EVERY BATH FOR EVERY PERIOD PROVIDED IN [dbo].[ftWetBenchReportingTimeline], REGARDLESS OF IF THERE WAS ACTIVITY
---- COMMENTED OUT AS IT WAS UNCLEAR TO ME WHETHER THIS WAS NECESSARY, BUT AVAILABLE IF REQUIRED

--WITH AllReportingPeriods AS (
--	SELECT 
--		CASE 
--			WHEN [Type] = 'Monthly' THEN 'Month ' + CAST([Interval] AS nvarchar) + ' | ' + CAST([Year] AS nvarchar)
--			WHEN [Type] = 'Shiftly' AND CAST([Date] AS TIME) <= '07:00:00' THEN Convert(nvarchar,[Date],102) + ' AM'
--			WHEN [Type] = 'Shiftly' AND CAST([Date] AS TIME) > '07:00:00' THEN Convert(nvarchar,[Date],102) + ' PM'
--			WHEN [Type] = 'Weekly' THEN TRIM([Name]) + ' | ' + CAST([Year] AS nvarchar)
--		END AS PeriodId
--		,*
--		, 1 AS link
--	FROM ftWetBenchReportingTimeline
--)

--,
--AllEquipmentBaths AS (
--	SELECT DISTINCT 
--		EquipmentID
--		,BathNo
--		,1 AS Link
--	FROM ftWetbench
--)


--SELECT 
--	ARP.PeriodId
--	,ARP.[Date]
--	,ARP.[Type]
--	,ARP.[Year]
--	,ARP.[Interval]
--	,ARP.[Name]
--	,AEB.EquipmentID
--	,AEB.BathNo
--	,COALESCE(A.Quantity, 0) AS Quantity
--	,COALESCE(A.Productivity,0) AS Productivity
--FROM AllReportingPeriods ARP
--INNER JOIN AllEquipmentBaths AEB ON ARP.link = AEB.Link
--INNER JOIN 
--	(SELECT 
--		RP.PeriodID
--		,EP.EquipmentID
--		,EP.BathNo
--		,EP.Quantity
--		,EP.Productivity
--	FROM #ReportingPeriod RP
--	INNER JOIN #EquipmentProductvity EP ON RP.PeriodID = EP.PeriodID
--	) A ON ARP.PeriodId = A.PeriodID AND AEB.EquipmentID = A.EquipmentID AND AEB.BathNo = A.BathNo
--order by [Type], [Year], [Interval], [Date], EquipmentID, BathNo