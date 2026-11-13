/* ============================================================
   BookNest - test accounts (DEVELOPMENT ONLY)

   Our login compares the typed password directly with the
   PasswordHash column, so these accounts store a plain password
   there. Never put a real password in this table.
   Safe to run more than once.
   ============================================================ */
USE BookNestDb;
GO

IF NOT EXISTS (SELECT 1 FROM Users WHERE Username = N'maria')
    INSERT INTO Users (FullName, Email, Username, PasswordHash, [Role])
    VALUES (N'Maria Santos', N'maria@booknest.ph', N'maria', N'maria123', 'member');

IF NOT EXISTS (SELECT 1 FROM Users WHERE Username = N'juan')
    INSERT INTO Users (FullName, Email, Username, PasswordHash, [Role])
    VALUES (N'Juan Dela Cruz', N'juan@booknest.ph', N'juan', N'juan123', 'member');

IF NOT EXISTS (SELECT 1 FROM Users WHERE Username = N'ana')
    INSERT INTO Users (FullName, Email, Username, PasswordHash, [Role])
    VALUES (N'Ana Reyes', N'ana@booknest.ph', N'ana', N'ana123', 'staff');

IF NOT EXISTS (SELECT 1 FROM Users WHERE Username = N'carlo')
    INSERT INTO Users (FullName, Email, Username, PasswordHash, [Role])
    VALUES (N'Carlo Mendoza', N'carlo@booknest.ph', N'carlo', N'carlo123', 'admin');
GO

SELECT UserId, Username, [Role] FROM Users ORDER BY UserId;
GO
