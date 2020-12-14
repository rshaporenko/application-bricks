CREATE PROCEDURE [Monitoring].[pub_Deployment_Log]
	@LogId UNIQUEIDENTIFIER = NULL,
	@Message NVARCHAR(MAX),
	--
	@Command NVARCHAR(MAX) = NULL, 
	@Result NVARCHAR(500) = NULL,
	@Exception NVARCHAR(MAX) = NULL,
	--
	@ObjectType VARCHAR(255) = NULL, 
	@ObjectName VARCHAR(255) = NULL
AS

	INSERT Monitoring.DeploymentLog
		(LogId, Message, Command, Result, Exception, ObjectType, ObjectName)
	VALUES
		(ISNULL(@LogId, NEWID()), @Message, @Command, @Result, @Exception, @ObjectType, @ObjectName)

RETURN 0
