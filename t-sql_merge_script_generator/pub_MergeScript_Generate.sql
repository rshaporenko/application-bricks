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
	DECLARE 
		@i INT = CHARINDEX('.', @SourceTable) --'].[' for imporovement

	DECLARE 
		@Schema VARCHAR(100) = IIF(@i = 0, 'dbo', LEFT(@SourceTable, @i - 1)),
		@Table VARCHAR(100) = IIF(@i = 0, @SourceTable, SUBSTRING(@SourceTable, @i + 1, 100) )

	IF LEFT(@Schema, 1) = '[' SET @Schema = RIGHT(@Schema, LEN(@Schema) - 1)
	IF LEFT(@Table, 1) = '[' SET @Table = RIGHT(@Table, LEN(@Table) - 1)
	   
	IF RIGHT(@Schema, 1) = ']' SET @Schema = LEFT(@Schema, LEN(@Schema) - 1)
	IF RIGHT(@Table, 1) = ']' SET @Table = LEFT(@Table, LEN(@Table) - 1)

	SET @SourceTable = '[' + @Schema + '].[' + @Table + ']'

	----
	DECLARE
		@fields VARCHAR(MAX), 
		@fieldsInsert VARCHAR(MAX), 
			
		@primaryFieldsList VARCHAR(1000), 
		@sql NVARCHAR(MAX)
	
			
	DECLARE @fieldsUpdate TABLE (Id INT IDENTITY, Line VARCHAR(MAX))
	DECLARE @res TABLE (Id INT IDENTITY, Line VARCHAR(MAX))

	DECLARE @upd TABLE (Field VARCHAR(MAX))

	SET NOCOUNT ON 

	DECLARE @tableId INT = (SELECT v.object_id 
								FROM 
									sys.tables v 
									JOIN sys.schemas s ON s.schema_id = v.schema_id 
								WHERE 
									s.name = @Schema AND v.name = @Table)

	IF @UpdateFields = '*'
	BEGIN
		INSERT @upd (Field)
		SELECT
			c.name
		FROM
			sys.columns AS c
			LEFT JOIN (
				SELECT 
					ic.object_id, ic.column_id, i.is_primary_key 
				FROM sys.index_columns AS ic
					JOIN sys.indexes i ON i.object_id = ic.object_id AND i.index_id = ic.index_id
			) AS tt ON c.object_id = tt.object_id AND tt.column_id = c.column_id
		WHERE
			c.object_id = @tableId
			AND ISNULL(tt.is_primary_key, 0) = 0
	END
	ELSE 
	BEGIN
		-- workaround as SSDT doesn't understand STRING_SPLIT for now
		INSERT @upd (Field) 
		EXEC sys.sp_executesql N'SELECT RTRIM(LTRIM(value)) FROM STRING_SPLIT(@UpdateFields, '','')', N'@UpdateFields VARCHAR(MAX)', @UpdateFields
	END


	DECLARE
		@SelectValuesList VARCHAR(MAX), @primaryFieldsWhere VARCHAR(MAX)


---------------------------------------------------------------------
	DECLARE
		@Columns TABLE 
		(
			Name NVARCHAR(128) NOT NULL,-- PRIMARY KEY, RS: no need to sort
			IsIdentity BIT NOT NULL,
			IsComputed BIT NOT NULL,
			TypeName NVARCHAR(128) NOT NULL,
			FullTypeName NVARCHAR(128) NOT NULL,
			IsPrimaryKey BIT NOT NULL
		)

	INSERT @Columns
	SELECT 
		--c.object_id, 
		c.name, c.is_identity, c.is_computed is_readonly, 
		UPPER(t.name) type_name, 
		UPPER(t.name) + IIF(t.name IN ('VARCHAR', 'NVARCHAR', 'CHAR', 'NCHAR', 'VARBINARY'), '(' + IIF(c.max_length = -1, 'MAX', CAST(c.max_length AS VARCHAR(100)))  + ')', '') full_type_name,
		ISNULL(tt.is_primary_key, 0)
	FROM
		sys.columns AS c
		JOIN sys.types t ON t.system_type_id = c.system_type_id AND t.user_type_id = c.user_type_id
		LEFT JOIN (
			SELECT ic.object_id, ic.column_id, i.is_primary_key FROM sys.index_columns AS ic
				JOIN sys.indexes i ON i.object_id = ic.object_id AND i.index_id = ic.index_id AND i.is_primary_key = 1
		) AS tt ON c.object_id = tt.object_id AND tt.column_id = c.column_id
	WHERE
		c.object_id = @tableId

	SELECT 
		@Fields = COALESCE(@Fields + ', ', '') + '[' + Name + ']',
		@FieldsInsert = COALESCE(@FieldsInsert + ', ', '') + 's.[' + Name + ']',
		@SelectValuesList = COALESCE(@SelectValuesList + ', ', '') +  
				IIF(ISNULL(TypeName, '') IN ('CHAR', 'NCHAR', 'VARCHAR', 'NVARCHAR', 'DATETIME', 'DATE'),
					'''+IIF([' + Name + '] IS NULL, ''NULL'', ''''''''+REPLACE([' + Name + '],'''''''','''''''''''')+'''''''')+ ''', 
					'''+ISNULL(CAST([' + Name +'] AS VARCHAR(MAX)),''NULL'')+''')
	FROM 
		@Columns

	INSERT @fieldsUpdate
		(Line)
	SELECT 
		CAST('		t.[' + c.Name + '] = s.[' + c.Name + '],' AS VARCHAR(MAX))
	FROM 
		@Columns c
		JOIN @upd u ON UPPER(u.Field) = UPPER(c.Name) 
	WHERE 
		c.IsPrimaryKey = 0

	UPDATE rr SET Line = LEFT(Line, LEN(Line) - 1)
	FROM
		@fieldsUpdate rr
		JOIN (SELECT TOP 1 Id FROM @fieldsUpdate ORDER BY Id DESC) r ON r.Id = rr.Id

	SELECT 
		@PrimaryFieldsList = COALESCE(@PrimaryFieldsList + ', ', '') + Name,
		@PrimaryFieldsWhere = COALESCE(@PrimaryFieldsWhere + ' AND ', '') + 't.'+ Name + ' = s.' + Name
	FROM 
		@Columns 
	WHERE 
		IsPrimaryKey = 1

-------------------------------------------------------------------------------------------------
INSERT @res	(Line) 
VALUES 
	('/* **** Generated by **** */'),
	('-- EXEC ' + OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID) + ' @SourceTable = ''' + @SourceTable + '''' 
		+ IIF(@UpdateFields ='*', '', ', @UpdateFields = ''' + ISNULL(@UpdateFields, NULL) + '''')
		+ IIF(@DataSource = '^Query', ', @DataSource = ''^Query''', '')
		+ IIF(@TargetTable IS NULL, '', ', @TargetTable = ''' + @TargetTable + '''')
		+ IIF(@IsForSSDT = 1, ', @IsForSSDT = 1', '')
	),
	('')

IF @IsForSSDT = 1
BEGIN
	INSERT @res	(Line) 
	VALUES 
		('PRINT ''Update rows in ' + @SourceTable + ''''),
		('GO'),
		('')
END

INSERT @res (Line) 
VALUES 
	('MERGE ' + ISNULL(@TargetTable, @SourceTable) + ' AS t /* Target */'), 
	('USING'), 
	('(')

IF @DataSource = '^Values'
BEGIN
	INSERT @res (Line) 
	VALUES 
		('	VALUES ')

	SET @sql = 'SELECT ''	(' + @SelectValuesList + '),'' FROM ' + @SourceTable + ISNULL(' WHERE ' + @SourceSearchCondition, '')
	--print @sql
	INSERT @res(Line)
	EXEC sys.sp_executesql @sql 

	UPDATE rr SET Line = LEFT(Line, LEN(Line) - 1)
	FROM
		@res rr
		JOIN (SELECT TOP 1 Id FROM @res ORDER BY Id DESC) r ON r.Id = rr.Id
END
ELSE IF  @DataSource = '^ParamValues'
BEGIN
	INSERT @res (Line) 
	VALUES 
		('	VALUES (' + @fieldsInsert + ')')
END
ELSE
BEGIN
	INSERT @res (Line) 
	VALUES 
		('	SELECT '),
		('		' + @fields),
		('	FROM '),
		('		' + @SourceTable)

	IF @SourceSearchCondition IS NOT NULL
	BEGIN
		INSERT @res (Line) 
		VALUES 
			('	WHERE ' + @SourceSearchCondition)
	END
END


INSERT @res (Line) 
VALUES 
	(')'),
	('AS s /* Source */ ' + IIF(@DataSource = '^Values', '(' + @fields + ')', '')),
	('ON ' + @primaryFieldsWhere),
	(''),
	('-- insert new rows'),
	('WHEN NOT MATCHED BY TARGET THEN'),
	('	INSERT'),
	('		(' +  @fields + ')'),
	('	VALUES'),
	('		(' +  @fieldsInsert + ')')

IF @Operations LIKE '%UPDATE%' AND EXISTS(SELECT NULL FROM @fieldsUpdate) 
BEGIN
	INSERT @res (Line) 
	VALUES 
		(''),
		('-- update matched rows'),
		('WHEN MATCHED THEN'),
		('	UPDATE SET')

	INSERT @res (Line) 
	SELECT Line FROM @fieldsUpdate
END

IF @Operations LIKE '%DELETE%'-- AND EXISTS(SELECT NULL FROM @fieldsUpdate)
BEGIN
	INSERT @res (Line) 
	VALUES 
		(''),
		('-- delete rows that are in the target but not the source'),
		('WHEN NOT MATCHED BY SOURCE' + ISNULL(' AND ' + @DeleteSearchCondition, '') +  ' THEN'),
		('	DELETE')
END

INSERT @res (Line) 
VALUES 
	(';')

IF @IsForSSDT = 1
BEGIN
	INSERT @res
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

SELECT Line AS Script FROM @res ORDER BY Id ASC

IF @IsForSSDT = 1
BEGIN
	SELECT ':r ..\Schemas\' + @Schema + '\PostDeployment\' + @Table + '.sql' as PostDeploymentLink
END

GO
