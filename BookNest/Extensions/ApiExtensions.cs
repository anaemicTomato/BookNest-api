using BookNest.Services;
using Microsoft.AspNetCore.Mvc;
using System.Globalization;
using System.Security.Claims;

namespace BookNest.Extensions
{
    public static class ApiExtensions
    {
        // The logged-in user's id, read from the token's "sub" claim
        public static int GetUserId(this ClaimsPrincipal user) => int.Parse(user.FindFirstValue("sub")!);

        // Same date format the Dashboard already uses
        public static string ToDisplay(this DateTime date) =>
            date.ToString("MMM d, yyyy", CultureInfo.InvariantCulture);

        // Success returns the data. Failure returns { message } with the right status code.
        public static IActionResult ToActionResult(this ServiceResult result) =>
            new ObjectResult(result.Success ? result.Data : new { message = result.Message })
            {
                StatusCode = result.StatusCode,
            };
    }
}
