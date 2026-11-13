using BookNest.Data;
using BookNest.Extensions;
using BookNest.Settings;
using BookNest.Services;
using BookNest.Settings;
using Dapper;
using Microsoft.AspNetCore.Connections;
using Microsoft.Extensions.Options;

namespace BookNest.Services;

public record NewLoan(int LoanId, DateTime DueDate);

public class LoanState
{
    public int LoanId { get; set; }
    public int UserId { get; set; }
    public int BookId { get; set; }
    public DateTime DueDate { get; set; }
    public DateTime? ReturnedAt { get; set; }
}

public class ReturnFine
{
    public decimal Amount { get; set; }
    public int DaysLate { get; set; }
}

public class ReserveCheck
{
    public bool HasLoan { get; set; }
    public bool HasReservation { get; set; }
    public bool CopyFree { get; set; }
}

public class LoanService(DatabaseConnection _context, IOptions<LoanSettings> options)
{
    private readonly LoanSettings _settings = options.Value;

    public async Task<ServiceResult> BorrowAsync(int userId, int bookId)
    {
        using var db = _context.CreateConnection();
        db.Open();
        using var tx = db.BeginTransaction();   // leaving without Commit() rolls back

        var exists = await db.ExecuteScalarAsync<int>(
            "SELECT COUNT(1) FROM Books WHERE BookId = @bookId AND IsArchived = 0",
            new { bookId }, tx);
        if (exists == 0) return ServiceResult.Fail(404, "Book not found.");

        var alreadyHas = await db.ExecuteScalarAsync<int>(
            "SELECT COUNT(1) FROM Loans WHERE UserId = @userId AND BookId = @bookId AND ReturnedAt IS NULL",
            new { userId, bookId }, tx);
        if (alreadyHas > 0) return ServiceResult.Fail(409, "You already have this book.");

        var activeLoans = await db.ExecuteScalarAsync<int>(
            "SELECT COUNT(1) FROM Loans WHERE UserId = @userId AND ReturnedAt IS NULL",
            new { userId }, tx);
        if (activeLoans >= _settings.MaxActiveLoans)
            return ServiceResult.Fail(409,
                $"You can borrow up to {_settings.MaxActiveLoans} books at a time. Return one first.");

        // Takes a copy only if one is free. Copies held for people whose reservation is
        // 'ready' are not free, unless the borrower is the one holding the reservation.
        var took = await db.ExecuteAsync(
            @"UPDATE Books
              SET AvailableCopies = AvailableCopies - 1
              WHERE BookId = @bookId AND IsArchived = 0 AND AvailableCopies > 0
                AND (AvailableCopies > (SELECT COUNT(*) FROM Reservations
                                        WHERE BookId = @bookId AND [Status] = 'ready')
                     OR EXISTS (SELECT 1 FROM Reservations
                                WHERE BookId = @bookId AND UserId = @userId AND [Status] = 'ready'))",
            new { bookId, userId }, tx);
        if (took == 0)
            return ServiceResult.Fail(409, "No copy is available right now. You can reserve this book instead.");

        var loan = await db.QuerySingleAsync<NewLoan>(
            @"INSERT INTO Loans (UserId, BookId, DueDate)
              OUTPUT INSERTED.LoanId, INSERTED.DueDate
              VALUES (@userId, @bookId, DATEADD(DAY, @loanDays, CAST(SYSDATETIME() AS DATE)))",
            new { userId, bookId, loanDays = _settings.LoanDays }, tx);

        // Borrowing a book closes this member's own reservation for it
        await db.ExecuteAsync(
            @"UPDATE Reservations SET [Status] = 'fulfilled'
              WHERE UserId = @userId AND BookId = @bookId AND [Status] IN ('ready', 'waiting')",
            new { userId, bookId }, tx);

        tx.Commit();
        return ServiceResult.Ok(new
        {
            loanId = loan.LoanId,
            dueDate = loan.DueDate.ToDisplay(),
            message = $"Borrowed. Due {loan.DueDate.ToDisplay()}.",
        });
    }

    public async Task<ServiceResult> ReserveAsync(int userId, int bookId)
    {
        using var db = _context.CreateConnection();

        var check = await db.QuerySingleOrDefaultAsync<ReserveCheck>(
            @"SELECT
                CAST(CASE WHEN EXISTS (SELECT 1 FROM Loans l
                                       WHERE l.UserId = @userId AND l.BookId = b.BookId AND l.ReturnedAt IS NULL)
                          THEN 1 ELSE 0 END AS BIT) AS HasLoan,
                CAST(CASE WHEN EXISTS (SELECT 1 FROM Reservations r
                                       WHERE r.UserId = @userId AND r.BookId = b.BookId
                                         AND r.[Status] IN ('waiting', 'ready'))
                          THEN 1 ELSE 0 END AS BIT) AS HasReservation,
                CAST(CASE WHEN b.AvailableCopies > (SELECT COUNT(*) FROM Reservations r2
                                                    WHERE r2.BookId = b.BookId AND r2.[Status] = 'ready')
                          THEN 1 ELSE 0 END AS BIT) AS CopyFree
              FROM Books b
              WHERE b.BookId = @bookId AND b.IsArchived = 0",
            new { userId, bookId });

        if (check is null) return ServiceResult.Fail(404, "Book not found.");
        if (check.HasLoan) return ServiceResult.Fail(409, "You already have this book.");
        if (check.HasReservation) return ServiceResult.Fail(409, "You are already on the waiting list for this book.");
        if (check.CopyFree) return ServiceResult.Fail(409, "A copy is available now. You can borrow it instead.");

        await db.ExecuteAsync(
            "INSERT INTO Reservations (UserId, BookId) VALUES (@userId, @bookId)",
            new { userId, bookId });

        var placeInLine = await db.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM Reservations WHERE BookId = @bookId AND [Status] = 'waiting'",
            new { bookId });

        return ServiceResult.Ok(new
        {
            placeInLine,
            message = $"Reserved. You are number {placeInLine} in line.",
        });
    }

    // onlyForUserId: a member can only return their own loans.
    // Pass null from a staff endpoint later so staff can return anyone's book.
    public async Task<ServiceResult> ReturnAsync(int loanId, int? onlyForUserId)
    {
        using var db = _context.CreateConnection();
        db.Open();
        using var tx = db.BeginTransaction();

        var loan = await db.QuerySingleOrDefaultAsync<LoanState>(
            "SELECT LoanId, UserId, BookId, DueDate, ReturnedAt FROM Loans WHERE LoanId = @loanId",
            new { loanId }, tx);
        if (loan is null || (onlyForUserId is not null && loan.UserId != onlyForUserId))
            return ServiceResult.Fail(404, "Loan not found.");

        var closed = await db.ExecuteAsync(
            @"UPDATE Loans SET ReturnedAt = CAST(SYSDATETIME() AS DATE)
              WHERE LoanId = @loanId AND ReturnedAt IS NULL",
            new { loanId }, tx);
        if (closed == 0) return ServiceResult.Fail(409, "This book was already returned.");

        await db.ExecuteAsync(
            "UPDATE Books SET AvailableCopies = AvailableCopies + 1 WHERE BookId = @bookId",
            new { bookId = loan.BookId }, tx);

        // A fine is created only when the book is late
        await db.ExecuteAsync(
            @"INSERT INTO Fines (LoanId, Amount)
              SELECT LoanId, DATEDIFF(DAY, DueDate, ReturnedAt) * @rate
              FROM Loans
              WHERE LoanId = @loanId AND ReturnedAt > DueDate",
            new { loanId, rate = _settings.FineRatePerDay }, tx);

        var fine = await db.QuerySingleOrDefaultAsync<ReturnFine>(
            @"SELECT f.Amount, DATEDIFF(DAY, l.DueDate, l.ReturnedAt) AS DaysLate
              FROM Fines f JOIN Loans l ON l.LoanId = f.LoanId
              WHERE f.LoanId = @loanId",
            new { loanId }, tx);

        // The first person waiting for this book becomes 'ready' (the copy is held for them)
        await db.ExecuteAsync(
            @"UPDATE Reservations SET [Status] = 'ready'
              WHERE ReservationId = (SELECT TOP (1) ReservationId FROM Reservations
                                     WHERE BookId = @bookId AND [Status] = 'waiting'
                                     ORDER BY ReservedAt)
                AND (SELECT AvailableCopies FROM Books WHERE BookId = @bookId)
                    > (SELECT COUNT(*) FROM Reservations WHERE BookId = @bookId AND [Status] = 'ready')",
            new { bookId = loan.BookId }, tx);

        tx.Commit();
        return ServiceResult.Ok(new
        {
            returnedLate = fine is not null,
            daysLate = fine?.DaysLate ?? 0,
            fineAmount = fine?.Amount ?? 0m,
        });
    }
}