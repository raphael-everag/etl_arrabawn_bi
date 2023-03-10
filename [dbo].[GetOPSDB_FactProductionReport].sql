USE [OPSDW]
GO
/****** Object:  StoredProcedure [dbo].[GetOPSDB_FactProductionReport]    Script Date: 02/03/2023 09:24:36 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Raphael Campos
-- Create date: 2023-Feb-09
-- Description:	Get data from OPSDB to load into Fact Table by using staging tables. 
-- =============================================
ALTER PROCEDURE [dbo].[GetOPSDB_FactProductionReport] 	

AS
-------------------------------------------------------------------------------- INTAKE & DISPATCH BEGIN ----------------------------------------------------------------------------------
DROP TABLE IF EXISTS #StagingIntakeDispatch
SELECT RootId,
       [Time In], 
	   [Time Out], 	   
	   [Product],
	   UnitId,
	   u.UnitName, 
	   'Ltrs' AS EngUnitName,
	   [Volume],
	   [Type]
INTO #StagingIntakeDispatch
FROM (
     SELECT RootId, UnitId, AttributeName, [Value]   
     FROM [OPS].[OPSDATA].[vwAttributeInstance] vw1
     WHERE VW1.AttributeId IN (1693, 1682, 1696, 1695, 1687) AND  
     vw1.unitID IN (5) 
--	 AND ROOTID IN (20757741, 20757375)
     AND vw1.AttributeTime > DATEADD(DAY, -180, GETDATE()) 
) T1
PIVOT (MAX([Value])
       FOR [AttributeName]
	   IN (
	   [Time In],
	   [Time Out],
	   [Product],
	   [Volume],
	   [Type]
		   )
	  ) AS T2
LEFT JOIN [OPS].[OPS].[UNIT] u ON u.Id = T2.UnitId


DROP TABLE IF EXISTS #AGGStagingIntakeDispatch;
SELECT CAST(SUBSTRING(sb.[Time In], 1,19) AS Datetime) ProductionSt, 
	   CAST(SUBSTRING(sb.[Time Out], 1,19) AS Datetime) ProductionEt,
	   sb.RootId,
	   'Intake' as AreaName,
	   sb.UnitId,
	   sb.Product as UnitName, 
	   sb.EngUnitName,
	   CASE WHEN sb.type in ('Delivered', 'Collected') THEN 1 ELSE 0 END AS 'Qty Loads',
	   ISNULL(CAST(sb.[Volume] AS DECIMAL(10,2)), 0) AS 'Volume Produced'
INTO #AGGStagingIntakeDispatch
FROM #StagingIntakeDispatch sb
WHERE sb.[Time In] IS NOT NULL 
AND Product IN ('SKIM MILK', 'Whole Milk Arr')

UNION ALL

SELECT CAST(SUBSTRING(sb.[Time In], 1,19) AS Datetime) ProductionSt, 
	   CAST(SUBSTRING(sb.[Time Out], 1,19) AS Datetime) ProductionEt,
	   sb.RootId,
	   'Dispatch' as AreaName,
	   sb.UnitId,
	   sb.Product as UnitName, 
	   sb.EngUnitName,
	   CASE WHEN sb.type in ('Delivered', 'Collected') THEN 1 ELSE 0 END AS 'Qty Loads', 
	   ISNULL(CAST(sb.[Volume] AS DECIMAL(10,2)), 0) AS 'Volume Produced'
FROM #StagingIntakeDispatch sb
WHERE sb.[Time In] IS NOT NULL 
AND Product IN ('CREAM', 'BUTTERMILK','RAW BUTTERMILK')

DROP TABLE IF EXISTS #AGGFinalStagingIntakeDispatch;
SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.ProductionSt AS EventSt,
	   agg.ProductionEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
INTO #AGGFinalStagingIntakeDispatch
FROM #AGGStagingIntakeDispatch agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName 
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.ProductionSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.ProductionSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('1', [Volume Produced]),
	  ('2', [Qty Loads])

) C (AttributeKey, AttributeValue)  


-------------------------------------------------------------------------------- INTAKE & DISPATCH END -----------------------------------------------------------------------------------------

-------------------------------------------------------------------------------- SEPARATION BEGIN -------------------------------------------------------------------------------------
DROP TABLE IF EXISTS #StagingSeparation;
SELECT RootId,
       [Production Start], 
	   [Production End], 	   
	   [CIP Start],
	   [CIP End],
	   [Production Step Start],
	   [Production Step End],
	   [Production Step Duration (mins)],
	   [Production Step Name],
	   'Separation' AS AreaName, 
	   UnitId,
	   u.UnitName, 
	   'Ltrs' AS EngUnitName,
	   CASE WHEN [Throughput] like '%E+%' OR [Throughput] like '%E-%' THEN CAST(CAST([Throughput] AS FLOAT) AS DECIMAL(10,2)) ELSE [Throughput] END AS Throughput,
	   [Production Duration (mins)],
	   [CIP Duration (mins)]
INTO #StagingSeparation
FROM (
    SELECT RootId, UnitId, AttributeName, [Value]
	FROM [OPS].[OPSDATA].[vwAttributeInstance] vw1
    WHERE VW1.AttributeId IN (2,3, 7, 1648, 201, 202, 203, 1650, 1651, 1653, 1654) AND  
    vw1.unitID IN (15,16,17,122) --Separator 2,3,5,6
    AND vw1.AttributeTime > DATEADD(DAY, -180, GETDATE()) 
--	and RootId IN (18865601, 19457642)
) T1
PIVOT (MAX([Value])
       FOR [AttributeName]
	   IN (
	   [Production Start],
	   [Production End],
	   [Throughput],
	   [Production Duration (mins)],
	   [CIP START],
	   [CIP END],
	   [CIP Duration (mins)],
	   [Production Step Start],
	   [Production Step End],
	   [Production Step Duration (mins)],
	   [Production Step Name]
		   )
	  ) AS T2
LEFT JOIN [OPS].[OPS].[UNIT] u ON u.Id = T2.UnitId	


DROP TABLE IF EXISTS #AGGStagingSeparation; 
SELECT CAST(SUBSTRING(sb.[Production Start], 1,19) AS Datetime) ProductionSt, 
	   CAST(SUBSTRING(sb.[Production End], 1,19) AS Datetime) ProductionEt,
	   sb.RootId,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   ISNULL(CAST(sb.[Throughput] AS DECIMAL(10,2)), 0) AS 'Volume',
	   ISNULL(CAST(sb.[Production Duration (mins)] AS DECIMAL(10,2))/60, 0) AS [Hours on Production]
INTO #AGGStagingSeparation
FROM #StagingSeparation sb
WHERE sb.[Production Start] IS NOT NULL 
--and RootId IN (18865601, 19457642)


DROP TABLE IF EXISTS #AGGStagingSeparation_CIP;
SELECT 
       CAST(SUBSTRING(sb.[CIP Start], 1,19) AS Datetime) CIPSt, 
	   CAST(SUBSTRING(sb.[CIP End], 1,19) AS Datetime) CIPEt,
	   sb.RootId,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   ISNULL(CAST(sb.[CIP Duration (mins)] AS DECIMAL(10,2))/60, 0) AS [Hours on CIP]
INTO #AGGStagingSeparation_CIP
FROM #StagingSeparation sb
WHERE sb.[CIP Start] IS NOT NULL 


DROP TABLE IF EXISTS #AGGStagingSeparation_WaterCirculation;
SELECT 
       CAST(SUBSTRING(sb.[Production Step Start], 1,19) AS Datetime) ProductionSt, 
	   CAST(SUBSTRING(sb.[Production Step End], 1,19) AS Datetime) ProductionEt,
	   sb.RootId,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   ISNULL(CAST(sb.[Production Step Duration (mins)] AS DECIMAL(10,2))/60, 0) AS [Hours on Water Circulation]
INTO #AGGStagingSeparation_WaterCirculation
FROM #StagingSeparation sb
WHERE sb.[Production Step Start] IS NOT NULL 
AND [Production Step Name] = 'Water Circulation'


DROP TABLE IF EXISTS #AGGFinalStagingSeparation;
SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.ProductionSt AS EventSt,
	   agg.ProductionEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
INTO #AGGFinalStagingSeparation
FROM #AGGStagingSeparation agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.ProductionSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.ProductionSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('3', [Hours on Production]),
	  ('1', [Volume])

) C (AttributeKey, AttributeValue)  

UNION ALL

SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.CIPSt AS EventSt,
	   agg.CIPEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
FROM #AGGStagingSeparation_CIP agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.CIPSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.CIPSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('4', [Hours on CIP])
) C (AttributeKey, AttributeValue)  

UNION ALL

SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.ProductionSt AS EventSt,
	   agg.ProductionEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
FROM #AGGStagingSeparation_WaterCirculation agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.ProductionSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.ProductionSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('6', [Hours on Water Circulation])
) C (AttributeKey, AttributeValue)  

-------------------------------------------------------------------------------- SEPARATION END -------------------------------------------------------------------------------------
 
-------------------------------------------------------------------------------- BUTTER BEGIN ----------------------------------------------------------------------------------
DROP TABLE IF EXISTS #StagingButter;
SELECT RootId,
       [Production Start], 
	   [Production End], 	   
	   'Butter' AS AreaName, 
	   UnitId,
	   u.UnitName,
	   CASE WHEN UnitId in (20,34) THEN 'Ltrs' ELSE 'Tonnes' END AS EngUnitName,
	   CASE WHEN UnitId = 20 THEN 
	   ISNULL(CAST([Throughput] AS DECIMAL(10,2)), 0)*1000 --Convert from M3 to Litres 
	   ELSE 
	   CASE WHEN UnitId = 106 THEN 
	   ISNULL(CAST([Quantity] AS DECIMAL(10,2)), 0)*25 --Convert from Kgs to Tonnes
	   ELSE 
	   CASE WHEN UnitId = 34 THEN
	   ISNULL(CAST([Cream From Silo 1] AS DECIMAL(10,2)), 0 ) + ISNULL(CAST([Cream From Silo 2] AS DECIMAL(10,2)), 0) + ISNULL(CAST([Cream From Silo 3] AS DECIMAL(10,2)), 0) + ISNULL(CAST([Cream From Silo 4] AS DECIMAL(10,2)),0)  
	   END END END AS Volume,
	   [Production Duration (mins)] 
INTO #StagingButter
FROM (
SELECT RootId, UnitId, AttributeName, [Value]
FROM [OPS].[OPSDATA].[vwAttributeInstance] vw1
WHERE VW1.AttributeId IN (2,3, 7, 1648, 1704, 1705, 1707, 1708, 1709) AND 
vw1.unitID in (20, 34, 106)  --20: Cream Pasteurizer; 34: Churn; 106: Butter Packer
AND vw1.AttributeTime > DATEADD(DAY, -180, GETDATE()) 
) T1
PIVOT (MAX([Value])
       FOR [AttributeName]
	   IN (
	   [Production Start],
	   [Production End],
	   [Production Duration (mins)],
	   [Throughput],
	   [Cream From Silo 1],
	   [Cream From Silo 2],
	   [Cream From Silo 3],
	   [Cream From Silo 4],
	   [Quantity]
		   )
	  ) AS T2
LEFT JOIN [OPS].[OPS].[UNIT] u ON u.Id = T2.UnitId		    


DROP TABLE IF EXISTS #AGGStagingButter;
SELECT CAST(SUBSTRING(sb.[Production Start], 1,19) AS Datetime) ProductionSt, 
	   CAST(SUBSTRING(sb.[Production End], 1,19) AS Datetime) ProductionEt,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   sb.RootId,
	   ISNULL(CAST(sb.[Volume] AS DECIMAL(10,2)), 0) AS Volume, 
	   ISNULL(CAST(sb.[Production Duration (mins)] AS DECIMAL(10,2))/60, 0) AS [Hours on Production] 
INTO #AGGStagingButter
FROM #StagingButter sb
WHERE sb.[Production Start] IS NOT NULL 


DROP TABLE IF EXISTS #AGGFinalStagingButter;
SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   de.EngUnitKey,
	   agg.RootId,
	   agg.ProductionSt AS EventSt,
	   agg.ProductionEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
INTO #AGGFinalStagingButter
FROM #AGGStagingButter agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimEngUnit de ON de.EngUnitName = agg.EngUnitName
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.ProductionSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.ProductionSt), 0) AS TIME) --Getting the start of hour
CROSS APPLY 
(
      VALUES 
	  ('1', Volume),
	  ('3', [Hours on Production])  
) C (AttributeKey, AttributeValue)   

	

-------------------------------------------------------------------------------- BUTTER END ----------------------------------------------------------------------------------

-------------------------------------------------------------------------------- CASEIN 1 & 2 BEGIN -------------------------------------------------------------------------------------
DROP TABLE IF EXISTS #StagingCasein
SELECT RootId,
       [Production Start], 
	   [Production End], 	   
	   CASE WHEN UNITID = 64 THEN 'Casein 1' ELSE 'Casein 2' END AS AreaName, 
	   UnitId,
	   u.UnitName,
	   DATEDIFF(MINUTE, [Production Start], [Production End]) AS [Production Duration (mins)], 
	   CASE WHEN [Throughput] like '%E+%' OR [Throughput] like '%E-%' THEN CAST(CAST([Throughput] AS FLOAT) AS DECIMAL(10,2)) ELSE [Throughput] END Volume,
	   'Ltrs' as EngUnitName
INTO #StagingCasein
FROM (
    SELECT RootId, UnitId, AttributeName, [Value]
	FROM [OPS].[OPSDATA].[vwAttributeInstance] vw1
    WHERE VW1.AttributeId IN (2,3, 7, 1648) AND 
    vw1.unitID in (64, 126) 
    AND vw1.AttributeTime > DATEADD(DAY, -180, GETDATE())
--  AND VW1.RootId = 19653730
) T1
PIVOT (MAX([Value])
       FOR [AttributeName]
	   IN (
	   [Production Start],
	   [Production End],
	   [Production Duration (mins)],
	   [Throughput]
		   )
	  ) AS T2
LEFT JOIN [OPS].[OPS].[UNIT] u ON u.Id = T2.UnitId		    
   

DROP TABLE IF EXISTS #AGGStagingCasein;
SELECT CAST(SUBSTRING(sb.[Production Start], 1,19) AS Datetime) ProductionSt, 
	   CAST(SUBSTRING(sb.[Production End], 1,19) AS Datetime) ProductionEt,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   sb.RootId,
	   CASE WHEN sb.UnitId = 126 THEN ISNULL(CAST(sb.[Volume] AS DECIMAL(10,2)), 0)*1000 ELSE ISNULL(CAST(sb.[Volume] AS DECIMAL(10,2)), 0) END AS Volume, 
	   ISNULL(CAST(sb.[Production Duration (mins)] AS DECIMAL(10,2))/60, 0) AS [Hours on Production],
	   CAST(ISNULL(CAST(sb.[Volume] AS DECIMAL(10,2)), 0)/NULLIF(CAST(sb.[Production Duration (mins)] AS DECIMAL(10,2))/60, 0) AS DECIMAL(10,2)) AS [Litres Per Hour]  
INTO #AGGStagingCasein
FROM #StagingCasein sb
WHERE sb.[Production Start] IS NOT NULL 


DROP TABLE IF EXISTS #AGGFinalStagingCasein  
SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.ProductionSt AS EventSt,
	   agg.ProductionEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
INTO #AGGFinalStagingCasein
FROM #AGGStagingCasein agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.ProductionSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.ProductionSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('1', Volume),
	  ('3', [Hours on Production]),
	  ('8', [Litres Per Hour])  
) C (AttributeKey, AttributeValue)  

-------------------------------------------------------------------------------- CASEIN 1 & 2 END -------------------------------------------------------------------------------------

-------------------------------------------------------------------------------- UO/NF BEGIN -------------------------------------------------------------------------------------
DROP TABLE IF EXISTS #StagingUONF;
SELECT RootId,
       [Production Start], 
	   [Production End], 	   
	   'UO/NF' AS AreaName, 
	   UnitId,
	   u.UnitName, 
	   CASE WHEN [Total Whey In] like '%E+%' OR [Total Whey In] like '%E-%' THEN CAST(CAST([Total Whey In] AS FLOAT) AS DECIMAL(10,2)) ELSE [Total Whey In] END AS [Total Whey In],
	   CASE WHEN [Total Concentrate] like '%E+%' OR [Total Whey In] like '%E-%' THEN CAST(CAST([Total Concentrate] AS FLOAT) AS DECIMAL(10,2)) ELSE [Total Concentrate] END [Total Concentrate],
	   CASE WHEN [Total Permeate] like '%E+%' OR [Total Whey In] like '%E-%' THEN CAST(CAST([Total Permeate] AS FLOAT) AS DECIMAL(10,2)) ELSE [Total Permeate] END [Total Permeate],
	   'Ltrs' as EngUnitName,
	   [Production Duration (mins)]
INTO #StagingUONF
FROM (
    SELECT RootId, UnitId, AttributeName, [Value]
	FROM [OPS].[OPSDATA].[vwAttributeInstance] vw1
    WHERE VW1.AttributeId IN (2,3, 7, 1648, 2667, 2669, 2668) AND 
    vw1.unitID in (70, 132) --UO & NF2 Plant 
    AND vw1.AttributeTime > DATEADD(DAY, -180, GETDATE())
) T1
PIVOT (MAX([Value])
       FOR [AttributeName]
	   IN (
	   [Production Start],
	   [Production End],
	   [Production Duration (mins)],
	   [Total Whey In],
	   [Total Concentrate],
	   [Total Permeate]
		   )
	  ) AS T2
LEFT JOIN [OPS].[OPS].[UNIT] u ON u.Id = T2.UnitId	

DROP TABLE IF EXISTS #AGGStagingUONF;
SELECT CAST(SUBSTRING(sb.[Production Start], 1,19) AS Datetime) ProductionSt, 
	   CAST(SUBSTRING(sb.[Production End], 1,19) AS Datetime) ProductionEt,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   sb.RootId,
	   ISNULL(CAST(sb.[Total Whey In] AS DECIMAL(10,2)), 0) AS 'Total Whey Processed',
	   ISNULL(CAST(sb.[Total Concentrate] AS DECIMAL(10,2)), 0) AS 'Total Conc Out',
	   ISNULL(CAST(sb.[Total Permeate] AS DECIMAL(10,2)), 0) AS 'Total Permeate Out', 
	   ISNULL(CAST(sb.[Production Duration (mins)] AS DECIMAL(10,2))/60, 0) AS [Hours on Production]
INTO #AGGStagingUONF
FROM #StagingUONF sb
WHERE sb.[Production Start] IS NOT NULL 


DROP TABLE IF EXISTS #AGGFinalStagingUONF;  
SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.ProductionSt AS EventSt,
	   agg.ProductionEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
INTO #AGGFinalStagingUONF
FROM #AGGStagingUONF agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.ProductionSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.ProductionSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('3', [Hours on Production]),
	  ('12', [Total Whey Processed]),
	  ('13', [Total Conc Out]),
	  ('14', [Total Permeate Out])
) C (AttributeKey, AttributeValue)  

-------------------------------------------------------------------------------- UO/NF END -------------------------------------------------------------------------------------

-------------------------------------------------------------------------------- EDT BEGIN -------------------------------------------------------------------------------------
DROP TABLE IF EXISTS #StagingEDT
SELECT RootId,
       [Production Start], 
	   [Production End], 	   
	   [CIP Start],
	   [CIP End],
	   'EDT' AS AreaName, 
	   UnitId,
	   u.UnitName, 
	   'Ltrs' AS EngUnitName,
	   Throughput,
	   [Production Duration (mins)],
	   [CIP Duration (mins)]
INTO #StagingEDT
FROM (
    SELECT RootId, UnitId, AttributeName, [Value]
	FROM [OPS].[OPSDATA].[vwAttributeInstance] vw1
    WHERE VW1.AttributeId IN (2,3, 7, 1648, 201, 202, 203) AND 
    vw1.unitID = 52  
    AND vw1.AttributeTime > DATEADD(DAY, -180, GETDATE()) 
) T1
PIVOT (MAX([Value])
       FOR [AttributeName]
	   IN (
	   [Production Start],
	   [Production End],
	   [Throughput],
	   [Production Duration (mins)],
	   [CIP START],
	   [CIP END],
	   [CIP Duration (mins)]
		   )
	  ) AS T2
LEFT JOIN [OPS].[OPS].[UNIT] u ON u.Id = T2.UnitId	


DROP TABLE IF EXISTS #AGGStagingEDT
SELECT CAST(SUBSTRING(sb.[Production Start], 1,19) AS Datetime) ProductionSt, 
	   CAST(SUBSTRING(sb.[Production End], 1,19) AS Datetime) ProductionEt,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   sb.RootId,
	   ISNULL(CAST(sb.[Throughput] AS DECIMAL(10,2)), 0) AS 'Volume',
	   ISNULL(CAST(sb.[Production Duration (mins)] AS DECIMAL(10,2))/60, 0) AS [Hours on Production],
	   CAST(ISNULL(CAST(sb.[Throughput] AS DECIMAL(10,2)), 0)/NULLIF(CAST(sb.[Production Duration (mins)] AS DECIMAL(10,2))/60, 0) AS DECIMAL(10,2)) AS [Average Thruput Per Hour]  
INTO #AGGStagingEDT
FROM #StagingEDT sb
WHERE sb.[Production Start] IS NOT NULL 

DROP TABLE IF EXISTS #AGGStagingEDT_CIP
SELECT 
       CAST(SUBSTRING(sb.[CIP Start], 1,19) AS Datetime) CIPSt, 
	   CAST(SUBSTRING(sb.[CIP End], 1,19) AS Datetime) CIPEt,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   sb.RootId,
	   ISNULL(CAST(sb.[CIP Duration (mins)] AS DECIMAL(10,2))/60, 0) AS [Hours on CIP]
INTO #AGGStagingEDT_CIP
FROM #StagingEDT sb
WHERE sb.[CIP Start] IS NOT NULL 
 

DROP TABLE IF EXISTS #AGGFinalStagingEDT  
SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.ProductionSt AS EventSt,
	   agg.ProductionEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
INTO #AGGFinalStagingEDT
FROM #AGGStagingEDT agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.ProductionSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.ProductionSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('3', [Hours on Production]),
	  ('1', [Volume]),
	  ('9', [Average Thruput Per Hour])

) C (AttributeKey, AttributeValue)  

UNION ALL

SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.CIPSt AS EventSt,
	   agg.CIPEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
FROM #AGGStagingEDT_CIP agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.CIPSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.CIPSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('4', [Hours on CIP])
) C (AttributeKey, AttributeValue)  

-------------------------------------------------------------------------------- EDT END -------------------------------------------------------------------------------------

-------------------------------------------------------------------------------- NIRO 1 BEGIN ----------------------------------------------------------------------------------
DROP TABLE IF EXISTS #StagingNiro1;
SELECT RootId,
       [Production Start], 
	   [Production End], 	   
	   [CIP Start],
	   [CIP End],
	   'Niro 1' AS AreaName, 
	   UnitId,
	   u.UnitName, 
	   'Ltrs' AS EngUnitName,
	   [Line A Feed Litres],
	   [Line B Feed Litres],
	   Throughput,
	   [Production Duration (mins)],
	   [CIP Duration (mins)]
INTO #StagingNiro1
FROM (  
     SELECT RootId, UnitId, AttributeName, [Value]   
     FROM [OPS].[OPSDATA].[vwAttributeInstance] vw1
     WHERE VW1.AttributeId IN (2,3,7, 2670, 2671, 1648, 201, 202, 203) AND  
     vw1.unitID = 61 
     AND vw1.AttributeTime > DATEADD(DAY, -180, GETDATE())
) T1
PIVOT (MAX([Value])
       FOR [AttributeName]
	   IN (
	   [Production Start],
	   [Production End],
	   [Line A Feed Litres],
	   [Line B Feed Litres],
	   [Throughput],
	   [Production Duration (mins)],
	   [CIP START],
	   [CIP END],
	   [CIP Duration (mins)]
		   )
	  ) AS T2
LEFT JOIN [OPS].[OPS].[UNIT] u ON u.Id = T2.UnitId	



DROP TABLE IF EXISTS #AGGStagingNiro1;
SELECT CAST(SUBSTRING(sb.[Production Start], 1,19) AS Datetime) ProductionSt, 
	   CAST(SUBSTRING(sb.[Production End], 1,19) AS Datetime) ProductionEt,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   sb.RootId,
	   ISNULL(CAST(sb.[Line A Feed Litres] AS DECIMAL(10,2)), 0) + ISNULL(CAST(sb.[Line B Feed Litres] AS DECIMAL(10,2)), 0) AS 'Total Volume',
	   ISNULL(CAST(sb.[Line A Feed Litres] AS DECIMAL(10,2)), 0) AS 'Line A Volume',
	   ISNULL(CAST(sb.[Line B Feed Litres] AS DECIMAL(10,2)), 0) AS 'Line B Volume',
	   ISNULL(CAST(sb.[Production Duration (mins)] AS DECIMAL(10,2))/60, 0) AS [Hours on Production],
	   CAST((ISNULL(CAST(sb.[Line A Feed Litres] AS DECIMAL(10,2)), 0) + ISNULL(CAST(sb.[Line B Feed Litres] AS DECIMAL(10,2)), 0))/NULLIF(CAST(sb.[Production Duration (mins)] AS DECIMAL(10,2))/60, 0) AS DECIMAL(10,2)) AS [Average Thruput Per Hour]
INTO #AGGStagingNiro1
FROM #StagingNiro1 sb
WHERE sb.[Production Start] IS NOT NULL 


--Calculate Hours on Production for Line A & Line B
DROP TABLE IF EXISTS #AGGStagingNiro1HoursonProductionLine_A;
SELECT ProductionSt,  
       ProductionEt,
	   sb.AreaName,
	   'Niro 1 Line A' AS UnitName, 
	   sb.EngUnitName,
	   sb.RootId,
	   sb.[Line A Volume] AS 'Volume',
	   CASE WHEN (sb.[Line A Volume] <> 0 and sb.[Total Volume] <> 0 and sb.[Hours on Production] <> 0) 
	   THEN CAST(sb.[Line A Volume]*sb.[Hours on Production]/sb.[Total Volume] AS DECIMAL(10,2))
	   ELSE 0 END AS [Hours on Production]
INTO #AGGStagingNiro1HoursonProductionLine_A
FROM #AGGStagingNiro1 sb

DROP TABLE IF EXISTS #AGGStagingNiro1HoursonProductionLine_B;
SELECT ProductionSt, 
       ProductionEt,
	   sb.AreaName,
	   'Niro 1 Line B' AS UnitName, 
	   sb.EngUnitName,
	   sb.RootId,
	   sb.[Line B Volume] AS 'Volume',
	   CASE WHEN (sb.[Line B Volume] <> 0 and sb.[Total Volume] <> 0 and sb.[Hours on Production] <> 0) 
	   THEN CAST(sb.[Line B Volume]*sb.[Hours on Production]/sb.[Total Volume] AS DECIMAL(10,2))
	   ELSE 0 END AS [Hours on Production]
INTO #AGGStagingNiro1HoursonProductionLine_B
FROM #AGGStagingNiro1 sb


DROP TABLE IF EXISTS #AGGStagingNiro1_CIP;
SELECT CAST(SUBSTRING(sb.[CIP Start], 1,19) AS Datetime)  CIPSt,
       CAST(SUBSTRING(sb.[CIP End], 1,19) AS Datetime) CIPEt,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   sb.RootId,
	   CAST(ISNULL(CAST(sb.[CIP Duration (mins)] AS DECIMAL(10,2))/60, 0) AS DECIMAL(10,2)) AS [Hours on CIP]
INTO #AGGStagingNiro1_CIP
FROM #StagingNiro1 sb
WHERE sb.[CIP Start] IS NOT NULL 


DROP TABLE IF EXISTS #AGGFinalStagingNiro1; 
SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.ProductionSt AS EventSt,
	   agg.ProductionEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
INTO #AGGFinalStagingNiro1
FROM #AGGStagingNiro1 agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.ProductionSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.ProductionSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('3', [Hours on Production]),
	  ('1', [Total Volume]),
	  ('9', [Average Thruput Per Hour])

) C (AttributeKey, AttributeValue)  

UNION ALL

SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.ProductionSt AS EventSt,
	   agg.ProductionEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
FROM #AGGStagingNiro1HoursonProductionLine_A agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.ProductionSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.ProductionSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('3', [Hours on Production]),
	  ('15', [Volume])

) C (AttributeKey, AttributeValue) 


UNION ALL

SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.ProductionSt AS EventSt,
	   agg.ProductionEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
FROM #AGGStagingNiro1HoursonProductionLine_B agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.ProductionSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.ProductionSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('3', [Hours on Production]),
	  ('16', [Volume])

) C (AttributeKey, AttributeValue) 

UNION ALL

SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.CIPSt AS EventSt,
	   agg.CIPEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
FROM #AGGStagingNiro1_CIP agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.CIPSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.CIPSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('4', [Hours on CIP])
) C (AttributeKey, AttributeValue)  


-------------------------------------------------------------------------------- NIRO 1 END ----------------------------------------------------------------------------------

-------------------------------------------------------------------------------- VDP BEGIN ----------------------------------------------------------------------------------
DROP TABLE IF EXISTS #StagingVDP;
SELECT RootId,
       [Production Start], 
	   [Production End], 	   
	   [CIP Start],
	   [CIP End],
	   'VDP' AS AreaName, 
	   UnitId,
	   u.UnitName, 
	   'Ltrs' AS EngUnitName,
	   Throughput,
	   [Production Duration (mins)],
	   [CIP Duration (mins)]
INTO #StagingVDP
FROM (  
      SELECT RootId, UnitId, AttributeName, [Value]   
      FROM [OPS].[OPSDATA].[vwAttributeInstance] vw1
      WHERE vw1.AttributeId IN (2,3,7, 1648, 201, 202, 203) AND  
            vw1.unitID = 50 
	-- AND ROOTID = 18902653
     AND vw1.AttributeTime > CONVERT(VARCHAR, (GETDATE() - 180))
) T1
PIVOT (MAX([Value])
       FOR [AttributeName]
	   IN (
	   [Production Start],
	   [Production End],
	   [CIP START],
	   [CIP END],
	   [Throughput],
	   [Production Duration (mins)],
	   [CIP Duration (mins)]
		   )
	  ) AS T2
LEFT JOIN [OPS].[OPS].[UNIT] u ON u.Id = T2.UnitId	

DROP TABLE IF EXISTS #AGGStagingVDP;
SELECT CAST(SUBSTRING(sb.[Production Start], 1,19) AS Datetime) ProductionSt, 
	   CAST(SUBSTRING(sb.[Production End], 1,19) AS Datetime) ProductionEt,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   sb.RootId,
	   ISNULL(CAST(sb.[Throughput] AS DECIMAL(10,2)), 0) AS 'Total Volume',
	   0 AS 'Total Lactose Addition', --Might need to get from IP21 Tag SPFM30
	   ISNULL(CAST(sb.[Production Duration (mins)] AS DECIMAL(10,2))/60, 0) AS [Hours on Production],
	   CAST(ISNULL(CAST(sb.[Throughput] AS DECIMAL(10,2)), 0)/NULLIF(CAST(sb.[Production Duration (mins)] AS DECIMAL(10,2))/60, 0) AS DECIMAL(10,2)) AS [Average Thruput Per Hour]
INTO #AGGStagingVDP
FROM #StagingVDP sb
WHERE sb.[Production Start] IS NOT NULL 


DROP TABLE IF EXISTS #AGGStagingVDP_CIP
SELECT CAST(SUBSTRING(sb.[CIP Start], 1,19) AS Datetime) CIPSt, 
       CAST(SUBSTRING(sb.[CIP End], 1,19) AS Datetime) CIPEt,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   sb.RootId,
	   ISNULL(CAST(sb.[CIP Duration (mins)] AS DECIMAL(10,2))/60, 0) AS [Hours on CIP]
INTO #AGGStagingVDP_CIP
FROM #StagingVDP sb
WHERE sb.[CIP Start] IS NOT NULL 


DROP TABLE IF EXISTS #AGGFinalStagingVDP;
SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.ProductionSt AS EventSt,
	   agg.ProductionEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
INTO #AGGFinalStagingVDP
FROM #AGGStagingVDP agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.ProductionSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.ProductionSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('3', [Hours on Production]),
	  ('1', [Total Volume]),
	  ('17', [Total Lactose Addition]),
	  ('9', [Average Thruput Per Hour])
) C (AttributeKey, AttributeValue)  

UNION ALL

SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.CIPSt AS EventSt,
	   agg.CIPEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
FROM #AGGStagingVDP_CIP agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.CIPSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.CIPSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('4', [Hours on CIP])
) C (AttributeKey, AttributeValue) 


-------------------------------------------------------------------------------- VDP END ---------------------------------------------------------------------------------


-------------------------------------------------------------------------------- NIRO2 START ---------------------------------------------------------------------------------

-- GET AVG TEMPERATURE FROM IP21 - WRITTEN BY KASEY TOBIN 
declare @ST datetime = dateadd(day, -7, current_timestamp)--'2023-01-01' 
declare @ET datetime = current_timestamp

-- When runs live 
--set @ST = dateadd(day, -365, current_timestamp)


declare @Results table 
(
      RootId int
      , UnitId int
      , ProductionStart datetime
      , ProductionEnd datetime
      , Throughput real
      , Duration real
      -- Value from IP21
      , AvgTemperature real
)


insert into @Results (RootId, UnitId, ProductionStart, ProductionEnd, Throughput, Duration)
SELECT 
      productionStart.RootId, 
      productionStart.UnitId, 
      productionStart.[Value] as ProductionStart, 
      productionEnd.Value as ProductionEnd, 
      throughput.Value, 
      duration.Value
FROM 
      [OPS].[OPSDATA].[vwDateTimeAttributeInstance] productionStart
      inner join [OPS].[OPSDATA].[vwDateTimeAttributeInstance] productionEnd on productionStart.RootId = productionEnd.RootId and productionEnd.AttributeId = 3
      inner join OPS.OPSDATA.vwNumericAttributeInstance throughput on throughput.RootId = productionStart.RootId and throughput.AttributeId = 1648 
      inner join OPS.OPSDATA.vwNumericAttributeInstance duration on duration.RootId = productionStart.RootId and duration.AttributeId = 7 
WHERE 
      productionStart.AttributeId IN (2)  -- ,3,7, 1648
      AND productionStart.unitID = 62
      and cast(cast(productionStart.Value as datetimeoffset) as datetime) > @ST
     and productionStart.RootId not in ( 17803999)

/*
SELECT RootId,
       UnitId,
	   cast([Production Start] as datetimeoffset) ProductionStart, 
	   cast([Production End] as datetimeoffset)  ProductionEnd, 
	   Throughput,
	   [Production Duration (mins)] Duration
FROM (  
     SELECT RootId, UnitId, AttributeName, [Value]   
     FROM [OPS].[OPSDATA].[vwAttributeInstance] vw1
     WHERE VW1.AttributeId IN (2,3,7, 1648) AND  
     vw1.unitID = 62 
	 --AND ROOTID = 17803999
     AND vw1.AttributeTime  >  dateadd(day, -365, current_timestamp)
) T1
PIVOT (MAX([Value])
       FOR [AttributeName]
	   IN (
	   [Production Start],
	   [Production End],
	   [Throughput],
	   [Production Duration (mins)]
		   )
	  ) AS T2
LEFT JOIN [OPS].[OPS].[UNIT] u ON u.Id = T2.UnitId	

select * from @Results
*/
-- cursor variables
declare @RootID int
      , @StartTime datetime
      , @EndTime datetime
      , @Query varchar(max)
DECLARE @IP21Value table (Result real)

declare IP21cursor CURSOR FOR

select 
      RootId
      , ProductionStart
      , ProductionEnd
from @Results

OPEN IP21Cursor;

FETCH NEXT FROM IP21cursor INTO @RootId, @StartTime, @EndTime
WHILE @@FETCH_STATUS = 0
BEGIN

      set @query = 'select AVG(IP_TREND_VALUE) from N2_TT6101 where IP_TREND_TIME between ''' + OPSDW.[dbo].[ToIP21DateFormat] (@StartTime) 
            + ''' and ''' + OPSDW.[dbo].[ToIP21DateFormat] (@EndTime) + ''' ' 

      insert into @IP21Value (Result)
      --print @query
      exec (@query) at IP21

      update @Results set AvgTemperature = (select top 1 Result from @IP21Value) 
      where RootId = @RootID

      delete from @IP21Value

FETCH NEXT FROM IP21cursor INTO @RootId, @StartTime, @EndTime
END
CLOSE IP21cursor;
DEALLOCATE IP21cursor;


DROP TABLE IF EXISTS #StagingNiro2AvgTemp
select RootId, 
       ProductionStart, 
	   ProductionEnd, 
	   UnitId,
	   CASE WHEN AvgTemperature > 185 THEN 'Niro 2 Milk' ELSE 'Niro 2 Whey' END AS UnitName, 
	   'Niro 2' AS AreaName,
	   'Ltrs' AS EngUnitName,
	   Throughput as 'Total Volume',  
	   Duration AS 'Production Duration (mins)' 
INTO #StagingNiro2AvgTemp
from @Results


DROP TABLE IF EXISTS #StagingNiro2CIP;
SELECT RootId,
	   [CIP Start],
	   [CIP End],
	   'Niro 2' AS AreaName, 
	   UnitId,
	   u.UnitName, 
	   'Ltrs' AS EngUnitName,
	   [CIP Duration (mins)]
INTO #StagingNiro2CIP
FROM (  
     SELECT RootId, UnitId, AttributeName, [Value]   
     FROM [OPS].[OPSDATA].[vwAttributeInstance] vw1
     WHERE VW1.AttributeId IN (201, 202, 203) AND  
     vw1.unitID = 62 
     AND vw1.AttributeTime > DATEADD(DAY, -180, GETDATE())
) T1
PIVOT (MAX([Value])
       FOR [AttributeName]
	   IN (
	   [CIP START],
	   [CIP END],
	   [CIP Duration (mins)]
		   )
	  ) AS T2
LEFT JOIN [OPS].[OPS].[UNIT] u ON u.Id = T2.UnitId	

DROP TABLE IF EXISTS #AGGStagingNiro2_CIP
SELECT CAST(SUBSTRING(sb.[CIP Start], 1,19) AS Datetime) CIPSt, 
       CAST(SUBSTRING(sb.[CIP End], 1,19) AS Datetime) CIPEt,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   sb.RootId,
	   ISNULL(CAST(sb.[CIP Duration (mins)] AS DECIMAL(10,2))/60, 0) AS [Hours on CIP]
INTO #AGGStagingNiro2_CIP
FROM #StagingNiro2CIP sb
WHERE sb.[CIP Start] IS NOT NULL 

DROP TABLE IF EXISTS #AGGStagingNiro2;
SELECT sb.RootId, 
       CAST(sb.[ProductionStart] AS Datetime) ProductionSt, 
	   CAST(sb.[ProductionEnd] AS Datetime) ProductionEt,
	   sb.AreaName,
	   sb.UnitId,
	   sb.UnitName, 
	   sb.EngUnitName,
	   sb.[Total Volume],
	   ISNULL(CAST(sb.[Production Duration (mins)] /60 AS DECIMAL(10,2)), 0)  AS [Hours on Production],
	   CAST(sb.[Total Volume] / (sb.[Production Duration (mins)] /60) AS DECIMAL(10,2)) AS [Average Thruput Per Hour]	  
INTO #AGGStagingNiro2
FROM #StagingNiro2AvgTemp sb


DROP TABLE IF EXISTS #AGGFinalStagingNiro2;
SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.ProductionSt AS EventSt,
	   agg.ProductionEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
INTO #AGGFinalStagingNiro2
FROM #AGGStagingNiro2 agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.ProductionSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.ProductionSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('3', [Hours on Production]),
	  ('1', [Total Volume]),
	  ('9', [Average Thruput Per Hour])
) C (AttributeKey, AttributeValue)  

UNION ALL

SELECT 
       dd.Datekey,
	   dt.TimeKey,
	   du.UnitKey,
	   da.AreaKey,
	   deu.EngUnitKey,
	   agg.RootId,
	   agg.CIPSt AS EventSt,
	   agg.CIPEt AS EventEt,
	   AttributeKey,
	  AttributeValue 
FROM #AGGStagingNiro2_CIP agg
LEFT JOIN [OPSDW].dbo.DimArea da ON da.areaname = agg.AreaName
LEFT JOIN [OPSDW].dbo.DimUnit du ON du.UnitName COLLATE DATABASE_DEFAULT =  agg.UnitName COLLATE DATABASE_DEFAULT 
LEFT JOIN [OPSDW].dbo.DimDate dd ON DD.DATE = CAST(agg.CIPSt AS DATE)
LEFT JOIN [OPSDW].dbo.DimTime dt ON dt.time30 = CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, agg.CIPSt), 0) AS TIME) --Getting the start of hour
LEFT JOIN [OPSDW].dbo.DimEngUnit deu ON deu.EngUnitName = agg.EngUnitName
CROSS APPLY 
(
      VALUES 
	  ('4', [Hours on CIP])
) C (AttributeKey, AttributeValue) 


-------------------------------------------------------------------------------- NIRO2 END ---------------------------------------------------------------------------------


DROP TABLE IF EXISTS #SourceFinalFactTable;
SELECT RootId, DateKey, TimeKey, UnitKey, AreaKey, EngUnitKey, EventSt, EventEt, AttributeKey, AttributeValue  
INTO #SourceFinalFactTable
FROM #AGGFinalStagingIntakeDispatch
UNION ALL
SELECT RootId, DateKey, TimeKey, UnitKey, AreaKey, EngUnitKey, EventSt, EventEt, AttributeKey, AttributeValue  
FROM #AGGFinalStagingSeparation
UNION ALL
SELECT RootId, DateKey, TimeKey, UnitKey, AreaKey, EngUnitKey, EventSt, EventEt, AttributeKey, AttributeValue  
FROM #AGGFinalStagingButter
UNION ALL
SELECT RootId, DateKey, TimeKey, UnitKey, AreaKey, EngUnitKey, EventSt, EventEt, AttributeKey, AttributeValue
FROM #AGGFinalStagingCasein
UNION ALL
SELECT RootId, DateKey, TimeKey, UnitKey, AreaKey, EngUnitKey, EventSt, EventEt, AttributeKey, AttributeValue
FROM #AGGFinalStagingUONF
UNION ALL
SELECT RootId, DateKey, TimeKey, UnitKey, AreaKey, EngUnitKey, EventSt, EventEt, AttributeKey, AttributeValue
FROM #AGGFinalStagingEDT
UNION ALL
SELECT RootId, DateKey, TimeKey, UnitKey, AreaKey, EngUnitKey, EventSt, EventEt, AttributeKey, AttributeValue
FROM #AGGFinalStagingVDP
UNION ALL
SELECT RootId, DateKey, TimeKey, UnitKey, AreaKey, EngUnitKey, EventSt, EventEt, AttributeKey, AttributeValue
FROM #AGGFinalStagingNiro1 
UNION ALL
SELECT RootId, DateKey, TimeKey, UnitKey, AreaKey, EngUnitKey, EventSt, EventEt, AttributeKey, AttributeValue
FROM #AGGFinalStagingNiro2 where rootid not in (17803999)

MERGE  OPSDW.dbo.FactProductionReport as TARGET
USING #SourceFinalFactTable as SOURCE
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



