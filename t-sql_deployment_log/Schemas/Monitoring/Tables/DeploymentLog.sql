CREATE TABLE [Monitoring].[DeploymentLog]
(
	[LogId] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY NONCLUSTERED,-- DEFAULT NEWID(), 
	[TimeStamp] DATETIME NOT NULL DEFAULT (GETDATE()),
	--
	[Message] NVARCHAR(MAX) NOT NULL,
	--
    [Command] NVARCHAR(MAX) NULL, 
    [Result] NVARCHAR(500) NULL,
	[Exception] NVARCHAR(MAX) NULL,
	--
    [ObjectType] VARCHAR(255) NULL, 
    [ObjectName] VARCHAR(255) NULL, 
	--

	[DbName] NVARCHAR(128) NULL CONSTRAINT [DF_Monitoring.DeploymentLog_DbName] DEFAULT DB_NAME(),
	[DbServer] NVARCHAR(128) NULL DEFAULT @@SERVERNAME,
	[Workstation] NVARCHAR(128) NULL DEFAULT HOST_NAME(),
	--
	[DbLogin] NVARCHAR(128) NULL CONSTRAINT [DF_Monitoring.DeploymentLog_SystemUser]  DEFAULT ORIGINAL_LOGIN(),
	[DbUser] NVARCHAR(128) NULL CONSTRAINT [DF_Monitoring.DeploymentLog_User]  DEFAULT USER_NAME(),
	[SessionId] SMALLINT NULL DEFAULT @@SPID,
)
GO

--@@SERVERNAME
-- SELECT @@SPID AS 'ID', SYSTEM_USER AS 'Login Name', USER AS 'User Name';
-- ObjectType: 'Deployment', ObjectName: DB_NAME(), Message: '', Result: '== Started ==' | '== Finished =='

/*
DECLARE	@DeploymentLogId VARCHAR(37) = '57DCD0A5-A870-462D-93FC-1F1D70CC32F3'

IF NOT EXISTS (SELECT NULL FROM [Monitoring].[DeploymentLog] WITH(NOLOCK) WHERE DeploymentLogID = @DeploymentLogID)
BEGIN

	DECLARE	@DeploymentCommand NVARCHAR(1000) = N'
			GRANT EXECUTE ON SCHEMA::[Tableau] TO [MyAlerts_AppUser];
			GRANT EXECUTE ON SCHEMA::[Tableau] TO [MyAlerts_ReadOnly];
		';

	EXECUTE sp_executesql @DeploymentCommand;

	DECLARE @DeploymentResult VARCHAR(255) = 'Tableau schema permissions successfully granted';
		
	INSERT [Monitoring].[DeploymentLog]	
		([DeploymentLogId], [DeploymentDescription], [CreateDateTime], [ObjectType], [ObjectName], [DeploymentCommand], [DeploymentResult])
	VALUES 
		(@DeploymentLogId, 'Grant permissions for [Tableau] schema', GETDATE(), 'Schema', 'Tableau', @DeploymentCommand, '');

	PRINT @DeploymentResult
END
GO
*/