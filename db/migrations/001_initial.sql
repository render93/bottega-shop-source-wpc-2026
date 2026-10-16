-- 001: checkouts recorded by the shop, completed and failed.
-- Applied by the environment preparation with an admin identity; the app user can only read and write rows.
IF OBJECT_ID('dbo.Checkouts') IS NULL
BEGIN
    CREATE TABLE dbo.Checkouts (
        Id bigint IDENTITY(1, 1) NOT NULL CONSTRAINT PK_Checkouts PRIMARY KEY,
        CreatedAt datetime2 NOT NULL CONSTRAINT DF_Checkouts_CreatedAt DEFAULT SYSUTCDATETIME(),
        Status varchar(16) NOT NULL CONSTRAINT CK_Checkouts_Status CHECK (Status IN ('Completed', 'Failed')),
        Amount decimal(10, 2) NOT NULL,
        Items nvarchar(200) NOT NULL,
        Promo nvarchar(32) NULL
    );
    CREATE INDEX IX_Checkouts_CreatedAt ON dbo.Checkouts (CreatedAt) INCLUDE (Status, Amount);
END
