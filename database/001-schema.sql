/* ============================================================
   BookNest library management system - SQL Server schema (database: BookNestDb)
   (lean version: 6 tables, written for Dapper)

   Dapper has no migrations, so THIS SCRIPT is the source of truth
   for the database.

   - Run in SSMS or Visual Studio's SQL Server Object Explorer.
     Run it once on a fresh database.
   - Column names are PascalCase so Dapper fills C# properties of
     the same name with no extra mapping (UserId -> UserId).
   - Nothing creates indexes for you, so this script adds the ones
     the app needs (see the Indexes section).
   - Later changes: add a numbered script (002-add-something.sql)
     instead of editing this one, and everyone runs the new file.
   - Starting over while testing: see the reset lines at the bottom.
   ============================================================ */

IF DB_ID(N'BookNestDb') IS NULL
    CREATE DATABASE BookNestDb;
GO
USE BookNestDb;
GO

/* ---------- Categories ---------- */
CREATE TABLE Categories (
    CategoryId  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Categories PRIMARY KEY,
    Name        NVARCHAR(100)     NOT NULL CONSTRAINT UQ_Categories_Name UNIQUE
);

/* ---------- Users (members, staff and admins share one table) ---------- */
CREATE TABLE Users (
    UserId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Users PRIMARY KEY,
    FullName      NVARCHAR(150)     NOT NULL,
    Email         NVARCHAR(256)     NOT NULL CONSTRAINT UQ_Users_Email UNIQUE,
    Username      NVARCHAR(50)      NOT NULL CONSTRAINT UQ_Users_Username UNIQUE,
    PasswordHash  NVARCHAR(255)     NOT NULL,
    [Role]        NVARCHAR(20)      NOT NULL
                  CONSTRAINT CK_Users_Role CHECK ([Role] IN ('member', 'staff', 'admin')),
    IsActive      BIT               NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT 1
);

/* ---------- Books ---------- */
CREATE TABLE Books (
    BookId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Books PRIMARY KEY,
    Title            NVARCHAR(255)     NOT NULL,
    Author           NVARCHAR(150)     NOT NULL,
    Isbn             NVARCHAR(20)      NOT NULL CONSTRAINT UQ_Books_Isbn UNIQUE,
    CategoryId       INT               NOT NULL
                     CONSTRAINT FK_Books_Categories REFERENCES Categories(CategoryId),
    TotalCopies      INT               NOT NULL CONSTRAINT DF_Books_TotalCopies DEFAULT 1,
    AvailableCopies  INT               NOT NULL CONSTRAINT DF_Books_AvailableCopies DEFAULT 1,
    IsArchived       BIT               NOT NULL CONSTRAINT DF_Books_IsArchived DEFAULT 0,
    -- guards against the two copy counts drifting out of sync
    CONSTRAINT CK_Books_Copies CHECK (AvailableCopies >= 0 AND AvailableCopies <= TotalCopies)
);

/* ---------- Loans ---------- */
CREATE TABLE Loans (
    LoanId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Loans PRIMARY KEY,
    UserId      INT               NOT NULL CONSTRAINT FK_Loans_Users REFERENCES Users(UserId),
    BookId      INT               NOT NULL CONSTRAINT FK_Loans_Books REFERENCES Books(BookId),
    BorrowedAt  DATE              NOT NULL CONSTRAINT DF_Loans_BorrowedAt DEFAULT (CAST(SYSDATETIME() AS DATE)),
    DueDate     DATE              NOT NULL,
    ReturnedAt  DATE              NULL,      -- NULL means the book is still out
    CONSTRAINT CK_Loans_DueDate CHECK (DueDate >= BorrowedAt)
);

/* ---------- Reservations ---------- */
CREATE TABLE Reservations (
    ReservationId  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Reservations PRIMARY KEY,
    UserId         INT               NOT NULL CONSTRAINT FK_Reservations_Users REFERENCES Users(UserId),
    BookId         INT               NOT NULL CONSTRAINT FK_Reservations_Books REFERENCES Books(BookId),
    ReservedAt     DATETIME2         NOT NULL CONSTRAINT DF_Reservations_ReservedAt DEFAULT SYSDATETIME(),
    [Status]       NVARCHAR(20)      NOT NULL CONSTRAINT DF_Reservations_Status DEFAULT 'waiting'
                   CONSTRAINT CK_Reservations_Status
                   CHECK ([Status] IN ('waiting', 'ready', 'fulfilled', 'cancelled'))
);

/* ---------- Fines (at most one per loan) ---------- */
CREATE TABLE Fines (
    FineId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Fines PRIMARY KEY,
    LoanId   INT               NOT NULL,
    Amount   DECIMAL(10,2)     NOT NULL CONSTRAINT CK_Fines_Amount CHECK (Amount >= 0),
    IsPaid   BIT               NOT NULL CONSTRAINT DF_Fines_IsPaid DEFAULT 0,
    CONSTRAINT UQ_Fines_LoanId UNIQUE (LoanId),    -- at most one fine per loan
    CONSTRAINT FK_Fines_Loans  FOREIGN KEY (LoanId) REFERENCES Loans(LoanId)
);
GO

/* ---------- Indexes ----------
   SQL Server does not index foreign key columns by itself, and with
   Dapper nothing else does it for you. These speed up the joins and
   lookups the queries use. (Users.Username, Users.Email, Books.Isbn
   and Fines.LoanId already get an index from their UNIQUE constraint.) */
CREATE INDEX IX_Books_CategoryId     ON Books(CategoryId);
CREATE INDEX IX_Loans_UserId         ON Loans(UserId, ReturnedAt);
CREATE INDEX IX_Loans_BookId         ON Loans(BookId);
CREATE INDEX IX_Reservations_UserId  ON Reservations(UserId);
CREATE INDEX IX_Reservations_BookId  ON Reservations(BookId, [Status], ReservedAt);
GO

/* ============================================================
   Starter data: categories and books only.
   Test accounts are in 002-test-accounts.sql and optional sample
   loans are in 003-demo-data.sql. Run the files in order.
   ============================================================ */
INSERT INTO Categories (Name) VALUES
    (N'Fiction'), (N'Science'), (N'History'), (N'Adventure');

INSERT INTO Books (Title, Author, Isbn, CategoryId, TotalCopies, AvailableCopies) VALUES
    (N'Noli Me Tangere',   N'José Rizal',       N'ISBN-0001', 1, 3, 3),
    (N'El Filibusterismo', N'José Rizal',       N'ISBN-0002', 1, 2, 2),
    (N'Frankenstein',      N'Mary Shelley',     N'ISBN-0003', 1, 1, 1),
    (N'Dracula',           N'Bram Stoker',      N'ISBN-0004', 1, 2, 2),
    (N'Treasure Island',   N'R. L. Stevenson',  N'ISBN-0005', 4, 2, 2),
    (N'Jane Eyre',         N'Charlotte Brontë', N'ISBN-0006', 1, 2, 2),
    (N'The Time Machine',  N'H. G. Wells',      N'ISBN-0007', 2, 2, 2);
GO


/*
Optional database guard

Two quick clicks of Borrow could slip past the checks at the same moment. This index makes the database refuse a second open loan of the same book by the same member. Run it once as 002-loan-guard.sql:

sql
*/
CREATE UNIQUE INDEX UX_Loans_OneOpenLoanPerMemberBook
    ON Loans(UserId, BookId) WHERE ReturnedAt IS NULL;
GO


/* ---------- Reset while testing (this deletes ALL the data) ----------
   Run these three lines on their own, then run this script again:

   USE master;
   ALTER DATABASE BookNest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
   DROP DATABASE BookNest;
*/
