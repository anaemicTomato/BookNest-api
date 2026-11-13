using BookNest.Data;
using BookNest.Models;
using BookNest.Services;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.Data;
using Microsoft.AspNetCore.Mvc;
using BookNest.DTOs;
using Dapper;

namespace BookNest.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class AuthController : ControllerBase
    {
        private readonly PasswordHasher<User> _hasher = new();
        private readonly DatabaseConnection _context;
        private readonly TokenService _tokenService;

        public AuthController(DatabaseConnection context, TokenService tokenService)
        {
            _context = context;
            _tokenService = tokenService;
        }

        [HttpPost("login")]
        public async Task<IActionResult> Login(LoginRequestDTO dto)
        {
            using var db = _context.CreateConnection();
            var user = await db.QuerySingleOrDefaultAsync<User>(
                @"SELECT UserId, FullName, Email, Username, PasswordHash, [Role], IsActive
              FROM Users WHERE Username = @Username AND IsActive = 1",
                new { dto.Username });

            if (user == null)
                return Unauthorized(new { message = "Invalid username or password." });

            if (dto.Password != user.PasswordHash)
                return Unauthorized(new { message = "Invalid username or password." });

            // Generate the JWT
            var token = _tokenService.GenerateToken(user);

            return Ok(new AuthResponseDTO
            {
                Token = token,
                Username = user.Username,
                FullName = user.FullName,
                Role = user.Role
            });
        }

        //[HttpPost("register")]
        //public async Task<IActionResult> Register(RegisterRequest req)
        //{
        //    if (string.IsNullOrWhiteSpace(req.FullName) || string.IsNullOrWhiteSpace(req.Email) ||
        //        string.IsNullOrWhiteSpace(req.Username) || req.Password is null || req.Password.Length < 8)
        //        return BadRequest(new { message = "Fill in every field. The password needs at least 8 characters." });

        //    using var db = factory.Create();
        //    var taken = await db.ExecuteScalarAsync<int>(
        //        "SELECT COUNT(1) FROM Users WHERE Username = @Username OR Email = @Email",
        //        new { req.Username, req.Email });
        //    if (taken > 0)
        //        return Conflict(new { message = "That username or email is already in use." });

        //    var hash = _hasher.HashPassword(new AppUser(), req.Password);
        //    await db.ExecuteAsync(
        //        @"INSERT INTO Users (FullName, Email, Username, PasswordHash, [Role])
        //      VALUES (@FullName, @Email, @Username, @PasswordHash, 'member')",
        //        new { req.FullName, req.Email, req.Username, PasswordHash = hash });

        //    return Ok();
        //}

        //private bool PasswordMatches(User user, string password)
        //{
        //    try
        //    {
        //        return _hasher.VerifyHashedPassword(user, user.PasswordHash, password)
        //               != PasswordVerificationResult.Failed;
        //    }
        //    catch (FormatException)
        //    {
        //        return false;   // the sample users in the SQL script have a placeholder hash
        //    }
        //}
    }
}
