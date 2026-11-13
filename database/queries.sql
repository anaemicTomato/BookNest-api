/* ============================================================
   BookNest - example queries, one per flowchart step (for Dapper)

   Run booknest-schema.sql first, then register at least one member
   through the API so there is a real UserId to test with
   (SELECT UserId, Username FROM Users).

   HOW TO USE A BLOCK
   - Each block starts with DECLARE lines so you can test it in SSMS:
     highlight the block and press Execute (F5).
   - In C#, copy the SQL WITHOUT the DECLARE lines and pass the same
     names as an anonymous object:

         using var db = factory.Create();
         var books = await db.QueryAsync<BookRow>(sql, new { Search, CategoryId });

   - Column aliases (AS Id) match the C# property names Dapper fills.
   - Dapper maps BIT to bool and DATE to DateTime.
   - GO only works in SSMS. Never put it in a C# string.
   - Blocks that change data are marked CHANGES DATA.
   ============================================================ */
USE BookNestDb;
GO

/* ---- Login: Valid credentials? ----
   Dapper: QuerySingleOrDefaultAsync<AppUser>(sql, new { Username })
   Check the password in C#, not in SQL (our login compares it in AuthController). */
DECLARE @Username NVARCHAR(50) = N'maria';

SELECT UserId, FullName, Email, Username, PasswordHash, [Role], IsActive
FROM Users
WHERE Username = @Username AND IsActive = 1;
GO


/* ---- Register account (CHANGES DATA) ----
   Dapper: ExecuteScalarAsync<int>(...) for the check, then ExecuteAsync(...)
   Make @PasswordHash in C#. The placeholder below can never log in,
   so delete the test row afterwards. */
DECLARE @FullName NVARCHAR(150) = N'Test Member',
        @Email NVARCHAR(256) = N'test@email.com',
        @Username NVARCHAR(50) = N'test.member',
        @PasswordHash NVARCHAR(255) = N'PLACEHOLDER_HASH';

SELECT COUNT(1) AS AlreadyTaken               -- must be 0 before inserting
FROM Users WHERE Username = @Username OR Email = @Email;

INSERT INTO Users (FullName, Email, Username, PasswordHash, [Role])
VALUES (@FullName, @Email, @Username, @PasswordHash, 'member');

DELETE FROM Users WHERE Username = @Username; -- clean up the test row
GO


/* ---- Browse and search the catalog ----
   Dapper: QueryAsync<BookRow>(sql, new { Search, CategoryId })
   Pass null to skip a filter. */
DECLARE @Search NVARCHAR(100) = NULL,
        @CategoryId INT = NULL;

SELECT b.BookId AS Id, b.Title, b.Author, c.Name AS Category, b.AvailableCopies
FROM Books b
JOIN Categories c ON c.CategoryId = b.CategoryId
WHERE b.IsArchived = 0
  AND (@CategoryId IS NULL OR b.CategoryId = @CategoryId)
  AND (@Search IS NULL OR b.Title LIKE N'%' + @Search + N'%'
                       OR b.Author LIKE N'%' + @Search + N'%')
ORDER BY b.Title;
GO


/* ---- Book details, and Copy available? ----
   Dapper: QuerySingleOrDefaultAsync<BookDetail>(sql, new { BookId })
   Show Borrow when AvailableCopies > 0, otherwise show Reserve. */
DECLARE @BookId INT = 1;

SELECT b.BookId AS Id, b.Title, b.Author, b.Isbn, c.Name AS Category,
       b.TotalCopies, b.AvailableCopies
FROM Books b
JOIN Categories c ON c.CategoryId = b.CategoryId
WHERE b.BookId = @BookId AND b.IsArchived = 0;
GO


/* ---- Borrow, due date set (CHANGES DATA, one transaction) ----
   In C#, run the two statements inside an IDbTransaction and pass it in.
   ExecuteAsync returns the number of rows changed, which replaces
   @@ROWCOUNT:

       using var db = factory.Create();
       db.Open();
       using var tx = db.BeginTransaction();

       var taken = await db.ExecuteAsync(
           "UPDATE Books SET AvailableCopies = AvailableCopies - 1 " +
           "WHERE BookId = @BookId AND AvailableCopies > 0",
           new { BookId }, tx);

       if (taken == 0) { tx.Rollback(); return Conflict(...); }   // no copy free

       await db.ExecuteAsync(
           "INSERT INTO Loans (UserId, BookId, DueDate) " +
           "VALUES (@UserId, @BookId, DATEADD(DAY, 14, CAST(SYSDATETIME() AS DATE)))",
           new { UserId, BookId }, tx);

       tx.Commit();

   The BEGIN TRAN version below is only for testing in SSMS. */
DECLARE @UserId INT = 1, @BookId INT = 1;

SET XACT_ABORT ON;
BEGIN TRAN;
    -- only succeeds if a copy is free, so two people cannot take the last copy
    UPDATE Books
    SET AvailableCopies = AvailableCopies - 1
    WHERE BookId = @BookId AND AvailableCopies > 0;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK;
        PRINT 'No copy available. Place a reservation instead.';
        RETURN;
    END

    INSERT INTO Loans (UserId, BookId, DueDate)
    VALUES (@UserId, @BookId, DATEADD(DAY, 14, CAST(SYSDATETIME() AS DATE)));
COMMIT;
GO


/* ---- Place reservation, when no copy is available (CHANGES DATA) ----
   Dapper: ExecuteAsync(sql, new { UserId, BookId })
   Returns 0 rows if the member already has an open reservation for this
   book, so answer with a 409 Conflict. */
DECLARE @UserId INT = 1, @BookId INT = 3;

INSERT INTO Reservations (UserId, BookId)
SELECT @UserId, @BookId
WHERE NOT EXISTS (
    SELECT 1 FROM Reservations
    WHERE UserId = @UserId AND BookId = @BookId AND [Status] IN ('waiting', 'ready')
);
GO


/* ---- Return book, then Returned late? Fine charged (CHANGES DATA, one transaction) ----
   Same pattern as borrowing: three ExecuteAsync calls on one IDbTransaction.
   If the first call returns 0 rows, the loan is missing or already returned,
   so roll back and answer with an error. */
DECLARE @LoanId INT = 1, @RatePerDay DECIMAL(10,2) = 5.00;

SET XACT_ABORT ON;
BEGIN TRAN;
    UPDATE Loans
    SET ReturnedAt = CAST(SYSDATETIME() AS DATE)
    WHERE LoanId = @LoanId AND ReturnedAt IS NULL;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK;
        PRINT 'Loan not found or already returned.';
        RETURN;
    END

    UPDATE Books
    SET AvailableCopies = AvailableCopies + 1
    WHERE BookId = (SELECT BookId FROM Loans WHERE LoanId = @LoanId);

    INSERT INTO Fines (LoanId, Amount)
    SELECT LoanId, DATEDIFF(DAY, DueDate, ReturnedAt) * @RatePerDay
    FROM Loans
    WHERE LoanId = @LoanId AND ReturnedAt > DueDate;
COMMIT;
GO


/* ---- When notified: who is first in line for a book ----
   Dapper: QuerySingleOrDefaultAsync<ReservationRow>(sql, new { BookId }) */
DECLARE @BookId INT = 3;

SELECT TOP (1) ReservationId AS Id, UserId
FROM Reservations
WHERE BookId = @BookId AND [Status] = 'waiting'
ORDER BY ReservedAt;
GO


/* ---- Pay fine: staff records the payment (CHANGES DATA) ----
   Dapper: ExecuteAsync(sql, new { FineId }). Returns 0 if already paid. */
DECLARE @FineId INT = 1;

UPDATE Fines SET IsPaid = 1 WHERE FineId = @FineId AND IsPaid = 0;
GO


/* ---- My Books: current checkouts, also used by the Dashboard ----
   Dapper: QueryAsync<BorrowedRow>(sql, new { UserId }) */
DECLARE @UserId INT = 1;

SELECT l.LoanId, b.BookId AS Id, b.Title, b.Author, l.BorrowedAt, l.DueDate,
       DATEDIFF(DAY, CAST(SYSDATETIME() AS DATE), l.DueDate) AS DaysLeft
FROM Loans l
JOIN Books b ON b.BookId = l.BookId
WHERE l.UserId = @UserId AND l.ReturnedAt IS NULL
ORDER BY l.DueDate;
GO


/* ---- My Books: reading history ---- */
DECLARE @UserId INT = 1;

SELECT l.LoanId, b.BookId AS Id, b.Title, b.Author, l.BorrowedAt, l.ReturnedAt,
       CASE WHEN l.ReturnedAt > l.DueDate THEN 1 ELSE 0 END AS WasLate
FROM Loans l
JOIN Books b ON b.BookId = l.BookId
WHERE l.UserId = @UserId AND l.ReturnedAt IS NOT NULL
ORDER BY l.ReturnedAt DESC;
GO


/* ---- Loan Status: a member's unpaid fines ----
   The Dashboard total is the SUM of these:
   ExecuteScalarAsync<decimal>("SELECT COALESCE(SUM(f.Amount), 0) ...") */
DECLARE @UserId INT = 1;

SELECT f.FineId, b.Title, f.Amount,
       DATEDIFF(DAY, l.DueDate, l.ReturnedAt) AS DaysLate
FROM Fines f
JOIN Loans l ON l.LoanId = f.LoanId
JOIN Books b ON b.BookId = l.BookId
WHERE l.UserId = @UserId AND f.IsPaid = 0;
GO


/* ---- Loan Status: a member's hold requests, with place in line ---- */
DECLARE @UserId INT = 1;

SELECT r.ReservationId AS Id, b.Title, r.[Status],
       (SELECT COUNT(*) FROM Reservations r2
        WHERE r2.BookId = r.BookId AND r2.[Status] = 'waiting'
          AND r2.ReservedAt <= r.ReservedAt) AS PlaceInLine
FROM Reservations r
JOIN Books b ON b.BookId = r.BookId
WHERE r.UserId = @UserId AND r.[Status] IN ('waiting', 'ready')
ORDER BY r.ReservedAt;
GO


/* ---- Dashboard: new arrivals ---- */
SELECT TOP (6) BookId AS Id, Title, Author
FROM Books
WHERE IsArchived = 0
ORDER BY BookId DESC;
GO


/* ---- Manage books: list every book, archived ones included ---- */
SELECT b.BookId AS Id, b.Title, b.Author, c.Name AS Category,
       b.TotalCopies, b.AvailableCopies, b.IsArchived
FROM Books b
JOIN Categories c ON c.CategoryId = b.CategoryId
ORDER BY b.Title;
GO


/* ---- Manage books: add a book (CHANGES DATA) ----
   A new book starts with every copy available. */
DECLARE @Title NVARCHAR(255) = N'Sample Book',
        @Author NVARCHAR(150) = N'Sample Author',
        @Isbn NVARCHAR(20) = N'ISBN-9999',
        @CategoryId INT = 2,
        @TotalCopies INT = 2;

INSERT INTO Books (Title, Author, Isbn, CategoryId, TotalCopies, AvailableCopies)
VALUES (@Title, @Author, @Isbn, @CategoryId, @TotalCopies, @TotalCopies);
GO


/* ---- Manage books: edit a book (CHANGES DATA) ----
   Changing TotalCopies also has to move AvailableCopies by the same amount,
   or the CHECK constraint on Books will reject the update. */
DECLARE @BookId INT = 1,
        @Title NVARCHAR(255) = N'Noli Me Tangere',
        @Author NVARCHAR(150) = N'José Rizal',
        @CategoryId INT = 1,
        @TotalCopies INT = 3;

UPDATE Books
SET Title = @Title,
    Author = @Author,
    CategoryId = @CategoryId,
    AvailableCopies = AvailableCopies + (@TotalCopies - TotalCopies),
    TotalCopies = @TotalCopies
WHERE BookId = @BookId;
GO


/* ---- Remove or archive books (CHANGES DATA) ----
   Hides the book and keeps its loan history. Use 0 to restore it. */
DECLARE @BookId INT = 5;

UPDATE Books SET IsArchived = 1 WHERE BookId = @BookId;
GO


/* ---- Manage member accounts: list members ---- */
SELECT u.UserId AS Id, u.FullName, u.Email, u.IsActive,
       (SELECT COUNT(*) FROM Loans l
        WHERE l.UserId = u.UserId AND l.ReturnedAt IS NULL) AS BooksOut
FROM Users u
WHERE u.[Role] = 'member'
ORDER BY u.FullName;
GO


/* ---- Manage member accounts: deactivate or reactivate (CHANGES DATA) ---- */
DECLARE @UserId INT = 2, @IsActive BIT = 0;

UPDATE Users SET IsActive = @IsActive WHERE UserId = @UserId;
GO


/* ---- Manage staff accounts (admin): list staff and admins ---- */
SELECT UserId AS Id, FullName, Email, Username, [Role], IsActive
FROM Users
WHERE [Role] IN ('staff', 'admin')
ORDER BY FullName;
GO


/* ---- Manage staff accounts (admin): change a role (CHANGES DATA) ----
   The API should only allow this for admins. */
DECLARE @UserId INT = 2, @Role NVARCHAR(20) = N'staff';

UPDATE Users SET [Role] = @Role WHERE UserId = @UserId;
GO


/* ---- Reports: Active loans ---- */
SELECT l.LoanId, u.FullName AS Member, b.Title, l.DueDate
FROM Loans l
JOIN Users u ON u.UserId = l.UserId
JOIN Books b ON b.BookId = l.BookId
WHERE l.ReturnedAt IS NULL
ORDER BY l.DueDate;
GO


/* ---- Reports: Overdue books ---- */
SELECT l.LoanId, u.FullName AS Member, b.Title,
       DATEDIFF(DAY, l.DueDate, CAST(SYSDATETIME() AS DATE)) AS DaysLate
FROM Loans l
JOIN Users u ON u.UserId = l.UserId
JOIN Books b ON b.BookId = l.BookId
WHERE l.ReturnedAt IS NULL AND l.DueDate < CAST(SYSDATETIME() AS DATE)
ORDER BY DaysLate DESC;
GO


/* ---- Reports: Popular books ---- */
SELECT TOP (5) b.BookId AS Id, b.Title, COUNT(*) AS TimesBorrowed
FROM Loans l
JOIN Books b ON b.BookId = l.BookId
GROUP BY b.BookId, b.Title
ORDER BY COUNT(*) DESC;
GO


/* ---- System metrics (admin dashboard) ----
   One row, so use QuerySingleAsync<Metrics>(sql). */
SELECT
    (SELECT COUNT(*) FROM Books WHERE IsArchived = 0)               AS TotalBooks,
    (SELECT COUNT(*) FROM Users WHERE [Role] = 'member')            AS Members,
    (SELECT COUNT(*) FROM Users WHERE [Role] IN ('staff', 'admin')) AS StaffAccounts,
    (SELECT COUNT(*) FROM Loans WHERE ReturnedAt IS NULL)           AS ActiveLoans;
GO
