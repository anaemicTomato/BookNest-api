# BookNest API

ASP.NET Core Web API (.NET 10) for the BookNest library management system.
Dapper + SQL Server, JWT login, Swagger. Roles: `member`, `staff`, `admin`.

The React front end lives in the **booknest-web** repository.

## Requirements
- Visual Studio 2026 with the **ASP.NET and web development** and **Data storage and processing** workloads
- .NET 10 SDK (installed with Visual Studio 2026)
- SQL Server (LocalDB comes with Visual Studio, or SQL Server Express/Developer) and optionally SSMS
- Git

## First-time setup
1. Clone this repo.
2. Create the database. Open the files in `database/` in Visual Studio's SQL Server Object Explorer or SSMS and run them in order:
   - `001-schema.sql` creates the `BookNestDb` database, the 6 tables and starter books
   - `002-test-accounts.sql` creates the test accounts
   - `003-demo-data.sql` (optional) adds sample loans, a fine and a reservation
3. Check `ConnectionStrings:DefaultConnection` in `BookNest/appsettings.json`. It uses `Server=localhost`.
   If your SQL Server has a different name, do not edit that file. Right-click the project, choose
   **Manage User Secrets**, and add your own value:
   ```json
   { "ConnectionStrings": { "DefaultConnection": "Server=(localdb)\\MSSQLLocalDB;Database=BookNestDb;Trusted_Connection=True;TrustServerCertificate=True;" } }
   ```
4. Open `BookNest.slnx`, choose the **https** profile and press **F5**.
   Swagger opens at https://localhost:7211/swagger.

## Test accounts (development only)
| Username | Password | Role |
|---|---|---|
| maria | maria123 | member |
| juan | juan123 | member |
| ana | ana123 | staff |
| carlo | carlo123 | admin |

In Swagger: `POST /api/auth/login`, copy the `token`, click **Authorize**, paste the token, then try any endpoint.

## Project structure
```
BookNest.slnx
BookNest/
  Common/          shared response types
  Controllers/     thin controllers (routes, roles, return results)
  Data/            DatabaseConnection (SQL Server connections for Dapper)
  DTOs/            request/response classes, names end with DTO
  Extensions/      helper methods (GetUserId, ToActionResult)
  Middleware/      ErrorHandlingMiddleware
  Models/          classes that match database tables
  Services/        business logic and transactions
  Settings/        classes bound to appsettings.json sections
database/          SQL scripts
```

## Working on the project
Read the team guide (`TEAM-GUIDE.md` in the booknest-web repo, `docs/` folder) before you start.
Branch from `main`, open a pull request, and ask a teammate to review it.
