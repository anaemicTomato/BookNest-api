using BookNest.Data;
using BookNest.Extensions;
using BookNest.Models;
using BookNest.Services;
using BookNest.Extensions;
using BookNest.Services;
using Dapper;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Connections;
using Microsoft.AspNetCore.Mvc;
using BookNest.DTOs;

namespace BookNest.Controllers;

[ApiController]
[Route("api/books")]
[Authorize]
public class BooksController(DatabaseConnection _context, LoanService loanService) : ControllerBase
{
    [HttpGet("/api/categories")]   // the leading slash makes this route absolute
    public async Task<IActionResult> Categories()
    {
        using var db = _context.CreateConnection();
        var rows = await db.QueryAsync<CategoryItemDTO>(
            "SELECT CategoryId AS Id, Name FROM Categories ORDER BY Name");
        return Ok(rows);
    }

    [HttpGet]
    public async Task<IActionResult> List(string? search, int? categoryId)
    {
        search = string.IsNullOrWhiteSpace(search) ? null : search.Trim();

        using var db = _context.CreateConnection();
        var rows = await db.QueryAsync<BookListItemDTO>(
            @"SELECT b.BookId AS Id, b.Title, b.Author, c.Name AS Category, b.AvailableCopies
              FROM Books b
              JOIN Categories c ON c.CategoryId = b.CategoryId
              WHERE b.IsArchived = 0
                AND (@categoryId IS NULL OR b.CategoryId = @categoryId)
                AND (@search IS NULL OR b.Title LIKE N'%' + @search + N'%'
                                     OR b.Author LIKE N'%' + @search + N'%')
              ORDER BY b.Title",
            new { search, categoryId });
        return Ok(rows);
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> Details(int id)
    {
        var userId = User.GetUserId();
        using var db = _context.CreateConnection();

        var book = await db.QuerySingleOrDefaultAsync<BookDetailDTO>(
            @"SELECT b.BookId AS Id, b.Title, b.Author, b.Isbn, c.Name AS Category,
                     b.TotalCopies, b.AvailableCopies,
                     CAST(CASE WHEN EXISTS (SELECT 1 FROM Loans l
                                            WHERE l.UserId = @userId AND l.BookId = b.BookId AND l.ReturnedAt IS NULL)
                               THEN 1 ELSE 0 END AS BIT) AS HasLoan,
                     CAST(CASE WHEN EXISTS (SELECT 1 FROM Reservations r
                                            WHERE r.UserId = @userId AND r.BookId = b.BookId
                                              AND r.[Status] IN ('waiting', 'ready'))
                               THEN 1 ELSE 0 END AS BIT) AS HasReservation,
                     CAST(CASE WHEN b.AvailableCopies > (SELECT COUNT(*) FROM Reservations r2
                                                         WHERE r2.BookId = b.BookId AND r2.[Status] = 'ready')
                                 OR EXISTS (SELECT 1 FROM Reservations r3
                                            WHERE r3.BookId = b.BookId AND r3.UserId = @userId
                                              AND r3.[Status] = 'ready')
                               THEN 1 ELSE 0 END AS BIT) AS CanBorrow
              FROM Books b
              JOIN Categories c ON c.CategoryId = b.CategoryId
              WHERE b.BookId = @id AND b.IsArchived = 0",
            new { id, userId });

        return book is null ? NotFound(new { message = "Book not found." }) : Ok(book);
    }

    [HttpPost("{id:int}/borrow")]
    [Authorize(Roles = "member")]
    public async Task<IActionResult> Borrow(int id) =>
        (await loanService.BorrowAsync(User.GetUserId(), id)).ToActionResult();

    [HttpPost("{id:int}/reserve")]
    [Authorize(Roles = "member")]
    public async Task<IActionResult> Reserve(int id) =>
        (await loanService.ReserveAsync(User.GetUserId(), id)).ToActionResult();
}