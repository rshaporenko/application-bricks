/********************************************************************************    
    
EXEC dbo.pub_MergeScript_Generate
	@SourceTable = 'dbo.Table1',
	@DataSource = '^Query', @TargetTable = 'TargetDatabase.dbo.Table1'

EXEC dbo.pub_MergeScript_Generate @SourceTable = 'dbo.Table1', @IsForSSDT = 1
    
**********************************************************************************/

CREATE PROCEDURE dbo.pub_MergeScript_Generate     
/*****************************************************************************************************************    
PURPOSE: Stored proc to generate repeatable data update scripts
*****************************************************************************************************************/    
	 @SourceTable VARCHAR(100), -- supports schema, dbo by default

	 @DataSource VARCHAR(100) = '^Values', -- ^Values OR ^Query OR ^ParamValues
	 @TargetTable VARCHAR(100) = NULL, -- Should be filled when @DataSource = ^TableQuery

	 @Operations VARCHAR(MAX) = 'INSERT,UPDATE,DELETE', -- INSERT,UPDATE,DELETE
	 @UpdateFields VARCHAR(MAX) = '*',

	 @SourceSearchCondition VARCHAR(MAX) = NULL,
	 @DeleteSearchCondition VARCHAR(MAX) = NULL,
	 
	 @IsForSSDT BIT = 0
AS
	-- parse table and schema names

	DECLARE 
		@i INT = CHARINDEX('.', @SourceTable) --'].[' for improvement

	DECLARE 
		@Schema VARCHAR(100) = IIF(@i = 0, 'dbo', LEFT(@SourceTable, @i - 1)),
		@Table VARCHAR(100) = IIF(@i = 0, @SourceTable, SUBSTRING(@SourceTable, @i + 1, 100) )

	IF LEFT(@Schema, 1) = '[' SET @Schema = RIGHT(@Schema, LEN(@Schema) - 1)
	IF LEFT(@Table, 1) = '[' SET @Table = RIGHT(@Table, LEN(@Table) - 1)
	   
	IF RIGHT(@Schema, 1) = ']' SET @Schema = LEFT(@Schema, LEN(@Schema) - 1)
	IF RIGHT(@Table, 1) = ']' SET @Table = LEFT(@Table, LEN(@Table) - 1)

	SET @SourceTable = '[' + @Schema + '].[' + @Table + ']'

	----
		
	SET NOCOUNT ON 

	DECLARE @tableId INT = (SELECT v.object_id 
								FROM 
									sys.tables v 
									JOIN sys.schemas s ON s.schema_id = v.schema_id 
								WHERE 
									s.name = @Schema AND v.name = @Table)
	
	---------------------------------------------------------------------
	DECLARE	@Columns TABLE 
		(
			Name NVARCHAR(128) NOT NULL,-- PRIMARY KEY, RS: no need to sort
			IsIdentity BIT NOT NULL,
			IsComputed BIT NOT NULL,
			TypeName NVARCHAR(128) NOT NULL,
			FullTypeName NVARCHAR(128) NOT NULL,
			IsPrimaryKey BIT NOT NULL,
			ToBeUpdated BIT NOT NULL
		)

	INSERT @Columns
	SELECT 
		--c.object_id, 
		c.name, c.is_identity, c.is_computed is_readonly, 
		UPPER(t.name) type_name, 
		UPPER(t.name) + IIF(t.name IN ('VARCHAR', 'NVARCHAR', 'CHAR', 'NCHAR', 'VARBINARY'), '(' + IIF(c.max_length = -1, 'MAX', CAST(c.max_length AS VARCHAR(100)))  + ')', '') full_type_name,
		ISNULL(tt.is_primary_key, 0),
		IIF(ISNULL(tt.is_primary_key, 0) = 0, 1, 0)
	FROM
		sys.columns AS c
		JOIN sys.types t ON t.system_type_id = c.system_type_id AND t.user_type_id = c.user_type_id
		LEFT JOIN (
			SELECT ic.object_id, ic.column_id, i.is_primary_key FROM sys.index_columns AS ic
				JOIN sys.indexes i ON i.object_id = ic.object_id AND i.index_id = ic.index_id AND i.is_primary_key = 1
		) AS tt ON c.object_id = tt.object_id AND tt.column_id = c.column_id
	WHERE
		c.object_id = @tableId


	--- INSERT fields
	DECLARE
		@ColumnList NVARCHAR(MAX), 
		@InsertValuesList NVARCHAR(MAX), 
		@SelectValuesList NVARCHAR(MAX)
		
	SELECT 
		@ColumnList = COALESCE(@ColumnList + ', ', '') + '[' + Name + ']',
		@InsertValuesList = COALESCE(@InsertValuesList + ', ', '') + 's.[' + Name + ']',
		@SelectValuesList = COALESCE(@SelectValuesList + ', ', '') +  
				IIF(ISNULL(TypeName, '') IN ('CHAR', 'NCHAR', 'VARCHAR', 'NVARCHAR', 'DATETIME', 'DATE'),
					'''+IIF([' + Name + '] IS NULL, ''NULL'', ''''''''+REPLACE([' + Name + '],'''''''','''''''''''')+'''''''')+ ''', 
					'''+ISNULL(CAST([' + Name +'] AS VARCHAR(MAX)),''NULL'')+''')
	FROM 
		@Columns

	-- identify update fields

	IF @UpdateFields <> '*'
	BEGIN
		UPDATE c
			SET c.ToBeUpdated = IIF(u.value IS NULL, 0, 1)
		FROM 
			@Columns c
			LEFT JOIN STRING_SPLIT(@UpdateFields, ',') u ON UPPER(RTRIM(LTRIM(u.value))) = UPPER(c.Name)
		WHERE 
			c.ToBeUpdated = 1
	END


	DECLARE @UpdateExpression TABLE (Id INT IDENTITY, Line NVARCHAR(MAX))
	INSERT @UpdateExpression
		(Line)
	SELECT 
		CAST('		t.[' + Name + '] = s.[' + Name + '],' AS NVARCHAR(MAX))
	FROM 
		@Columns
	WHERE
		ToBeUpdated = 1

	UPDATE @UpdateExpression SET Line = LEFT(Line, LEN(Line) - 1)
	WHERE
		Id = (SELECT TOP 1 Id FROM @UpdateExpression ORDER BY Id DESC)

	-----
	DECLARE
		@primaryFieldsList NVARCHAR(1000), 
		@primaryFieldsWhere NVARCHAR(MAX)

	SELECT 
		@PrimaryFieldsList = COALESCE(@PrimaryFieldsList + ', ', '') + Name,
		@PrimaryFieldsWhere = COALESCE(@PrimaryFieldsWhere + ' AND ', '') + 't.'+ Name + ' = s.' + Name
	FROM 
		@Columns 
	WHERE 
		IsPrimaryKey = 1

-------------------------------------------------------------------------------------------------
DECLARE @Script TABLE (Id INT IDENTITY, Line NVARCHAR(MAX))
INSERT @Script	(Line) 
VALUES 
	('/* **** Generated by ****'),
	('EXEC ' + OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID) + ' @SourceTable = ''' + @SourceTable + '''' 
		+ IIF(@UpdateFields ='*', '', ', @UpdateFields = ''' + ISNULL(@UpdateFields, NULL) + '''')
		+ IIF(@DataSource = '^Query', ', @DataSource = ''^Query''', '')
		+ IIF(@TargetTable IS NULL, '', ', @TargetTable = ''' + @TargetTable + '''')
		+ IIF(@IsForSSDT = 1, ', @IsForSSDT = 1', '')
	),
	('*/')

IF @IsForSSDT = 1
BEGIN
	INSERT @Script	(Line) 
	VALUES 
		('PRINT ''Update rows in ' + @SourceTable + ''''),
		('GO'),
		('')
END

INSERT @Script (Line) 
VALUES 
	('MERGE ' + ISNULL(@TargetTable, @SourceTable) + ' AS t /* Target */'), 
	('USING'), 
	('(')

IF @DataSource = '^Values'
BEGIN
	INSERT @Script (Line) 
	VALUES 
		('	VALUES ')

	DECLARE @sql NVARCHAR(MAX) = 'SELECT ''	(' + @SelectValuesList + '),'' FROM ' + @SourceTable + ISNULL(' WHERE ' + @SourceSearchCondition, '')
	--print @sql
	INSERT @Script(Line)
	EXEC sys.sp_executesql @sql 

	UPDATE @Script SET Line = LEFT(Line, LEN(Line) - 1)
	WHERE Id = (SELECT TOP 1 Id FROM @Script ORDER BY Id DESC)
END
ELSE IF  @DataSource = '^ParamValues'
BEGIN
	INSERT @Script (Line) 
	VALUES 
		('	VALUES (' + @InsertValuesList + ')')
END
ELSE
BEGIN
	INSERT @Script (Line) 
	VALUES 
		('	SELECT '),
		('		' + @ColumnList),
		('	FROM '),
		('		' + @SourceTable)

	IF @SourceSearchCondition IS NOT NULL
	BEGIN
		INSERT @Script (Line) 
		VALUES 
			('	WHERE ' + @SourceSearchCondition)
	END
END


INSERT @Script (Line) 
VALUES 
	(')'),
	('AS s /* Source */ ' + IIF(@DataSource = '^Values', '(' + @ColumnList + ')', '')),
	('ON ' + @primaryFieldsWhere),
	(''),
	('-- insert new rows'),
	('WHEN NOT MATCHED BY TARGET THEN'),
	('	INSERT'),
	('		(' +  @ColumnList + ')'),
	('	VALUES'),
	('		(' +  @InsertValuesList + ')')

IF @Operations LIKE '%UPDATE%' AND EXISTS(SELECT NULL FROM @UpdateExpression) 
BEGIN
	INSERT @Script (Line) 
	VALUES 
		(''),
		('-- update matched rows'),
		('WHEN MATCHED THEN'),
		('	UPDATE SET')

	INSERT @Script (Line) 
	SELECT Line FROM @UpdateExpression
END

IF @Operations LIKE '%DELETE%'-- AND EXISTS(SELECT NULL FROM @fieldsUpdate)
BEGIN
	INSERT @Script (Line) 
	VALUES 
		(''),
		('-- delete rows that are in the target but not the source'),
		('WHEN NOT MATCHED BY SOURCE' + ISNULL(' AND ' + @DeleteSearchCondition, '') +  ' THEN'),
		('	DELETE')
END

INSERT @Script (Line) 
VALUES 
	(';')

IF @IsForSSDT = 1
BEGIN
	INSERT @Script
		(Line) 
	VALUES
		('GO'),
		(''),
		('PRINT '''''),
		('PRINT ''Operation applied ' + @SourceTable + ''''),
		('PRINT '''''),
		('GO')
END

IF @IsForSSDT = 1
BEGIN
	SELECT @Table + '.sql' as ScriptFileName
END

SELECT Line AS Script FROM @Script ORDER BY Id ASC

IF @IsForSSDT = 1
BEGIN
	SELECT ':r ..\Schemas\' + @Schema + '\PostDeployment\' + @Table + '.sql' as PostDeploymentLink
END

GO
