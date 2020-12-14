CREATE TABLE [Monitoring].[DeploymentLog]
(
	[LogId] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY NONCLUSTERED,
	[TimeStamp] DATETIME NOT NULL CONSTRAINT [DF_Monitoring.DeploymentLog_TimeStamp] DEFAULT (GETDATE()),
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
	[DbServer] NVARCHAR(128) NULL CONSTRAINT [DF_Monitoring.DeploymentLog_DbServer] DEFAULT @@SERVERNAME,
	[Workstation] NVARCHAR(128) NULL CONSTRAINT [DF_Monitoring.DeploymentLog_Workstation] DEFAULT HOST_NAME(),
	--
	[DbLogin] NVARCHAR(128) NULL CONSTRAINT [DF_Monitoring.DeploymentLog_DbLogin]  DEFAULT ORIGINAL_LOGIN(),
	[DbUser] NVARCHAR(128) NULL CONSTRAINT [DF_Monitoring.DeploymentLog_DbUser]  DEFAULT USER_NAME(),
	[SessionId] SMALLINT NULL CONSTRAINT [DF_Monitoring.DeploymentLog_SessionId] DEFAULT @@SPID,
)
