USE [OPSDW]
GO
/****** Object:  StoredProcedure [dbo].[GetIP21_AvgTemp_Niro_FactProductionReport]    Script Date: 02/03/2023 09:26:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		Raphael Campos
-- Create date: 2023-Feb-27
-- Description:	Get Average Temp + Supply Fan data while off production from IP21 to load into Fact Table by using staging tables. 
-- =============================================
ALTER PROCEDURE [dbo].[GetIP21_AvgTemp_Niro_FactProductionReport] 
AS


-- Period 2 in this example (assuming current time is 15:44) 
declare @ST_Period datetime = DATEADD(DAY, DATEDIFF(DAY, 1, GETDATE()), 0)   --@STProcessing start of previous period (in this case last day)
declare @ET_Period datetime = DATEADD(MS, -2, DATEADD(DD, 0, DATEDIFF(DD, 0, GETDATE()))) -- @ETProcessing start of previous period  (in this case last hour from last day)

declare @ResultsNiro1 table 
(
      
        StartTime datetime
      , EndTime datetime
      , Tagname varchar(50)
      , AttributeValue real
)

DECLARE @QUERYNiro1 VARCHAR(MAX) = 'Get_AvgTemp_Niro1_BI (''' + OPSDW.[dbo].[ToIP21DateFormat] (@ST_Period) + ''', ''' + OPSDW.[dbo].[ToIP21DateFormat] (@ET_Period) + ''');'
INSERT INTO @ResultsNiro1(Tagname, AttributeValue)
EXEC (@QUERYNIRO1) at IP21

UPDATE @ResultsNiro1 
SET StartTime = @ST_Period,
    EndTime = @ET_Period

DROP TABLE IF EXISTS #StagingIP21Niro1Data  
SELECT ABS(CAST(CAST(NEWID() AS VARBINARY) AS INT)) as RootId, 
       StartTime, 
	   EndTime, 
	   'Niro 1' AreaName,
	   'Niro 1 Dryer' UnitName,
	   CASE WHEN Tagname = 'N1_SC6101' THEN 'Celsius' ELSE '%' END AS EngUnitName,
	   CASE WHEN Tagname = 'N1_SC6101' THEN 'AvgTemp' ELSE 'AvgSupplierFan' END AS AttributeName,
	   AttributeValue 
 INTO #StagingIP21Niro1Data 
 FROM @ResultsNiro1


declare @ResultsNiro2 table 
(
      
        StartTime datetime
      , EndTime datetime
      , Tagname varchar(50)
      , AttributeValue real
)

DECLARE @QUERYNIRO2 VARCHAR(MAX) = 'Get_AvgTemp_Niro2_BI (''' + OPSDW.[dbo].[ToIP21DateFormat] (@ST_Period) + ''', ''' + OPSDW.[dbo].[ToIP21DateFormat] (@ET_Period) + ''');'
INSERT INTO @ResultsNiro2(Tagname, AttributeValue)
EXEC (@QUERYNIRO2) at IP21

UPDATE @ResultsNiro2 
SET StartTime = @ST_Period,
    EndTime = @ET_Period

DROP TABLE IF EXISTS #StagingIP21Niro2Data  
SELECT ABS(CAST(CAST(NEWID() AS VARBINARY) AS INT)) as RootId, 
       StartTime, 
	   EndTime, 
	   'Niro 2' AreaName,
	   'Niro 2 Dryer' UnitName,
	   CASE WHEN Tagname = 'N2_SC6104' THEN 'Celsius' ELSE '%' END AS EngUnitName,
	   CASE WHEN Tagname = 'N2_SC6104' THEN 'AvgTemp' ELSE 'AvgSupplierFan' END AS AttributeName,
	   AttributeValue 
 INTO #StagingIP21Niro2Data 
 FROM @ResultsNiro2


DROP TABLE IF EXISTS #StagingIP21Niro	      
SELECT RootId, 
       StartTime,
	   EndTime,
	   AreaName,
	   UnitName,
	   EngUnitName,
	   ISNULL([AvgTemp], 0) AS [AvgTemp],
	   ISNULL([AvgSupplierFan], 0) AS [AvgSupplierFan]
INTO #StagingIP21Niro
FROM (	    
SELECT RootId, 
       StartTime, 
	   EndTime, 
	   AreaName,
	   UnitName,
	   EngUnitName,
	   AttributeName,
	   AttributeValue
       FROM #StagingIP21Niro1Data
UNION ALL
SELECT RootId, 
       StartTime, 
	   EndTime, 
	   AreaName,
	   UnitName,
	   EngUnitName,
	   AttributeName,
	   AttributeValue
       FROM #StagingIP21Niro2Data
) T1
PIVOT (MAX([AttributeValue])
      FOR [AttributeName]
	  IN ([AvgTemp], 
	      [AvgSupplierFan]
		  )
      ) AS T2 
	  
	  
DROP TABLE IF EXISTS #SourceFinalStagingIP21Niro;
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
INTO #SourceFinalStagingIP21Niro
FROM #StagingIP21Niro agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dds ON dds.DATE = CAST(agg.StartTime AS DATE)
LEFT JOIN [OPSDW].dbo.DimDate dde ON dde.DATE = CAST(agg.EndTime AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(agg.StartTime AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('18', [AvgTemp]),
	  ('19', [AvgSupplierFan])
) C (AttributeKey, AttributeValue)  



--If already exists, delete from fact table to avoid duplicates. 
DELETE FROM OPSDW.dbo.FactProductionReport 
WHERE AreaKey IN (11, 12) and AttributeKey in (18,19)
AND EventSt = @ST_Period 
AND EventEt = @ET_Period

MERGE  OPSDW.dbo.FactProductionReport as TARGET
USING #SourceFinalStagingIP21Niro as SOURCE
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

