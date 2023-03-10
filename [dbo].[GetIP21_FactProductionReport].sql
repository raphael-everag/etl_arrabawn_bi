USE [OPSDW]
GO
/****** Object:  StoredProcedure [dbo].[GetIP21_FactProductionReport]    Script Date: 02/03/2023 09:25:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		Raphael Campos
-- Create date: 2023-Feb-10
-- Description:	Get data from IP21 to load into Fact Table by using staging tables. 
-- =============================================
ALTER PROCEDURE [dbo].[GetIP21_FactProductionReport] --@STProcessing datetime, @ETProcessing datetime	
AS

-- Have ability to run this query for whatever time period you want 
-- Usually this will be the current day (and maybe yesterday), but give the ability to reprocess
--DECLARE @STProcessing datetime = GETDATE()
--DECLARE @ETProcessing datetime = CURRENT_TIMESTAMP

-- Loop through each frequency period within this time range 
-- Assume doing daily initially 

-- Then call the existing production report for each time period 
-- Period 1 in this example
--declare @ST_Period datetime = '2023-02-06 00:00:00' -- start of current period (in this case day)
--declare @ET_Period datetime = '2023-02-07 00:00:00' -- start of current hour

-- Period 2 in this example (assuming current time is 15:44) 
declare @ST_Period datetime = DATEADD(DAY, DATEDIFF(DAY, 0, GETDATE()), 0)   --@STProcessing start of current period (in this case day)
declare @ET_Period datetime = DATEADD(HOUR, DATEDIFF(HOUR, 0, GETDATE()), 0) -- @ETProcessing start of current hour

declare @Results table 
(
      groupIndex int
      , StartTime datetime
      , EndTime datetime
      , Title varchar(255)
      , AreaName varchar(255)
      , unitName varchar(255)
      , Volume real
      , PercentageFull real
      , Eng varchar(255)      
      -- Added fields
)

DECLARE @QUERY VARCHAR(MAX) = 'Get_DailyProd_BI (''' + OPSDW.[dbo].[ToIP21DateFormat] (@ST_Period) + ''', ''' + OPSDW.[dbo].[ToIP21DateFormat] (@ET_Period) + ''');'
INSERT INTO @Results(groupIndex, Title, AreaName, unitName, Volume, PercentageFull, Eng)
EXEC (@QUERY) at IP21

UPDATE @Results 
SET StartTime = @ST_Period,
    EndTime = @ET_Period

DROP TABLE IF EXISTS #StagingIP21Data  
SELECT ABS(CAST(CAST(NEWID() AS VARBINARY) AS INT)) as RootId, 
       StartTime, 
	   EndTime, 
	   GroupIndex, 
	   Title, 
	   AreaName, 
	   UnitName, 
	   ISNULL(Volume, 0) AS Volume, 
	   ISNULL(PercentageFull, 0) AS PercentageFull, 
	   Eng  
INTO #StagingIP21Data
FROM @Results

DROP TABLE IF EXISTS #SourceFinalStagingIP21Data;
SELECT agg.RootId,
	   dde.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.StartTime AS EventSt,
	   agg.EndTime AS EventEt,
	   AttributeKey,
	  AttributeValue 
INTO #SourceFinalStagingIP21Data
FROM #StagingIP21Data agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dds ON dds.DATE = CAST(agg.StartTime AS DATE)
LEFT JOIN [OPSDW].dbo.DimDate dde ON dde.DATE = CAST(agg.EndTime AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(agg.StartTime AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.Eng
CROSS APPLY 
(
      VALUES 
	  ('1', [Volume]),
	  ('7', PercentageFull)
) C (AttributeKey, AttributeValue)  
WHERE agg.Title = 'Closing Stock'


--If already exists, delete from fact table to avoid duplicates. 
DELETE FROM OPSDW.dbo.FactProductionReport 
WHERE UnitKey in (10,11,12,13,14,15,16,17, 18, 19, 20, 21, 22)
AND EventSt = @ST_Period 
AND EventEt = @ET_Period

MERGE  OPSDW.dbo.FactProductionReport as TARGET
USING #SourceFinalStagingIP21Data as SOURCE
ON (
	TARGET.RootId = SOURCE.RootId and 
	TARGET.AttributeKey = Source.AttributeKey and
	TARGET.UnitKey = Source.UnitKey
)
WHEN MATCHED 
THEN 
	UPDATE 
	SET 
		  TARGET.TimeKey = SOURCE.TimeKey, 
	      TARGET.UnitKey = SOURCE.UnitKey,
          TARGET.AreaKey = SOURCE.AreaKey,
	      TARGET.EngUnitKey = SOURCE.EngUnitKey,
	      TARGET.EventSt = SOURCE.EventSt,
	      TARGET.EventEt = SOURCE.EventEt,
		  TARGET.AttributeKey = SOURCE.AttributeKey,
		  TARGET.[Value] = SOURCE.[AttributeValue]
WHEN NOT MATCHED BY TARGET
THEN
	INSERT ([RootId],[DateKey],[TimeKey],[UnitKey], [AreaKey],[EngUnitKey],[EventSt],[EventEt],[AttributeKey],[Value])
	VALUES (
		SOURCE.[RootId],
		SOURCE.[DateKey],
		SOURCE.[TimeKey],
		SOURCE.[UnitKey],
		SOURCE.[AreaKey],
		SOURCE.[EngUnitKey],
		SOURCE.[EventSt],
		SOURCE.[EventEt],
		SOURCE.[AttributeKey],
		SOURCE.[AttributeValue]);

