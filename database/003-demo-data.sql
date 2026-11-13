/* ============================================================
   BookNest - optional demo data so the screens have something to show
   Run after 001-schema.sql and 002-test-accounts.sql.
   Does nothing if the Loans table already has rows.

   After it runs:
   - maria has two books out (Noli Me Tangere due in 2 days, Frankenstein due in 14 days)
   - juan returned Dracula 3 days late and has an unpaid 15.00 fine
   - juan is waiting for Frankenstein (its only copy is out)
   ============================================================ */
USE BookNestDb;
GO

IF NOT EXISTS (SELECT 1 FROM Loans)
BEGIN
    DECLARE @maria INT = (SELECT UserId FROM Users WHERE Username = N'maria');
    DECLARE @juan  INT = (SELECT UserId FROM Users WHERE Username = N'juan');
    DECLARE @noli  INT = (SELECT BookId FROM Books WHERE Isbn = N'ISBN-0001');
    DECLARE @frank INT = (SELECT BookId FROM Books WHERE Isbn = N'ISBN-0003');
    DECLARE @drac  INT = (SELECT BookId FROM Books WHERE Isbn = N'ISBN-0004');
    DECLARE @today DATE = CAST(SYSDATETIME() AS DATE);

    INSERT INTO Loans (UserId, BookId, BorrowedAt, DueDate) VALUES
        (@maria, @noli,  DATEADD(DAY, -12, @today), DATEADD(DAY, 2,  @today)),
        (@maria, @frank, @today,                    DATEADD(DAY, 14, @today));
    UPDATE Books SET AvailableCopies = AvailableCopies - 1 WHERE BookId IN (@noli, @frank);

    INSERT INTO Loans (UserId, BookId, BorrowedAt, DueDate, ReturnedAt)
    VALUES (@juan, @drac, DATEADD(DAY, -17, @today), DATEADD(DAY, -3, @today), @today);
    INSERT INTO Fines (LoanId, Amount) VALUES (SCOPE_IDENTITY(), 15.00);

    INSERT INTO Reservations (UserId, BookId) VALUES (@juan, @frank);
END
GO
