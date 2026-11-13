using BookNest.Data;
using BookNest.DTOs;
using BookNest.Extensions;
using BookNest.Services;
using BookNest.Settings;
using Dapper;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Connections;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using System.Globalization;
using System.Security.Claims;

namespace BookNest.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class MemberController(
    DatabaseConnection _context,
    LoanService loanService,
    IOptions<LoanSettings> loanOptions) : ControllerBase
    {
        private const string CurrentLoansSql =
            @"SELECT l.LoanId, b.BookId AS Id, b.Title, b.Author, l.BorrowedAt, l.DueDate,
                 DATEDIFF(DAY, CAST(SYSDATETIME() AS DATE), l.DueDate) AS DaysLeft
          FROM Loans l
          JOIN Books b ON b.BookId = l.BookId
          WHERE l.UserId = @userId AND l.ReturnedAt IS NULL
          ORDER BY l.DueDate";

        private static object ToJson(BorrowedRowDTO b) => new
        {
            b.LoanId,
            b.Id,
            b.Title,
            b.Author,
            borrowedAt = b.BorrowedAt.ToDisplay(),
            dueDate = b.DueDate.ToDisplay(),
            b.DaysLeft,
        };

        [HttpGet("dashboard")]
        public async Task<IActionResult> Dashboard()
        {
            var userId = User.GetUserId();
            using var db = _context.CreateConnection();

            var borrowed = await db.QueryAsync<BorrowedRowDTO>(CurrentLoansSql, new { userId });

            var unpaidFines = await db.ExecuteScalarAsync<decimal>(
                @"SELECT COALESCE(SUM(f.Amount), 0)
              FROM Fines f JOIN Loans l ON l.LoanId = f.LoanId
              WHERE l.UserId = @userId AND f.IsPaid = 0",
                new { userId });

            var newArrivals = await db.QueryAsync<ArrivalRowDTO>(
                @"SELECT TOP (6) BookId AS Id, Title, Author
              FROM Books WHERE IsArchived = 0 ORDER BY BookId DESC");

            return Ok(new { unpaidFines, borrowed = borrowed.Select(ToJson), newArrivals });
        }

        [HttpGet("loans")]
        public async Task<IActionResult> CurrentLoans()
        {
            using var db = _context.CreateConnection();
            var rows = await db.QueryAsync<BorrowedRowDTO>(CurrentLoansSql, new { userId = User.GetUserId() });
            return Ok(rows.Select(ToJson));
        }

        [HttpGet("history")]
        public async Task<IActionResult> History()
        {
            using var db = _context.CreateConnection();
            var rows = await db.QueryAsync<HistoryRowDTO>(
                @"SELECT l.LoanId, b.BookId AS Id, b.Title, b.Author, l.BorrowedAt, l.ReturnedAt,
                     CAST(CASE WHEN l.ReturnedAt > l.DueDate THEN 1 ELSE 0 END AS BIT) AS WasLate
              FROM Loans l
              JOIN Books b ON b.BookId = l.BookId
              WHERE l.UserId = @userId AND l.ReturnedAt IS NOT NULL
              ORDER BY l.ReturnedAt DESC, l.LoanId DESC",
                new { userId = User.GetUserId() });

            return Ok(rows.Select(h => new
            {
                h.LoanId,
                h.Id,
                h.Title,
                h.Author,
                borrowedAt = h.BorrowedAt.ToDisplay(),
                returnedAt = h.ReturnedAt.ToDisplay(),
                h.WasLate,
            }));
        }

        [HttpGet("loan-status")]
        public async Task<IActionResult> LoanStatus()
        {
            var userId = User.GetUserId();
            using var db = _context.CreateConnection();

            var deadlines = await db.QueryAsync<BorrowedRowDTO>(CurrentLoansSql, new { userId });

            var holds = await db.QueryAsync<HoldRowDTO>(
                @"SELECT r.ReservationId AS Id, b.Title, r.[Status],
                     (SELECT COUNT(*) FROM Reservations r2
                      WHERE r2.BookId = r.BookId AND r2.[Status] = 'waiting'
                        AND r2.ReservedAt <= r.ReservedAt) AS PlaceInLine
              FROM Reservations r
              JOIN Books b ON b.BookId = r.BookId
              WHERE r.UserId = @userId AND r.[Status] IN ('waiting', 'ready')
              ORDER BY r.ReservedAt",
                new { userId });

            var fines = (await db.QueryAsync<FineRowDTO>(
                @"SELECT f.FineId, b.Title, f.Amount, DATEDIFF(DAY, l.DueDate, l.ReturnedAt) AS DaysLate
              FROM Fines f
              JOIN Loans l ON l.LoanId = f.LoanId
              JOIN Books b ON b.BookId = l.BookId
              WHERE l.UserId = @userId AND f.IsPaid = 0
              ORDER BY f.FineId",
                new { userId })).ToList();

            return Ok(new
            {
                deadlines = deadlines.Select(ToJson),
                holds,
                fines,
                totalUnpaid = fines.Sum(f => f.Amount),
                finePerDay = loanOptions.Value.FineRatePerDay,
            });
        }

        [HttpPost("loans/{loanId:int}/return")]
        public async Task<IActionResult> Return(int loanId) =>
            (await loanService.ReturnAsync(loanId, User.GetUserId())).ToActionResult();
    }
}
