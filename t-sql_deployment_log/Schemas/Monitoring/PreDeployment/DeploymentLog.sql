IF OBJECT_ID(N'[Monitoring].[pub_Deployment_Log]', 'P') IS NOT NULL
BEGIN
    EXEC Monitoring.pub_Deployment_Log 
        @Message = '== Started ==', @ObjectType = 'Deployment', @Command = 'DatabaseName = "$(DatabaseName)"'
END