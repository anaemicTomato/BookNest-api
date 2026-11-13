namespace BookNest.DTOs
{
    public class BorrowedRowDTO
    {
        public int LoanId { get; set; }
        public int Id { get; set; }
        public string Title { get; set; }
        public string Author { get; set; }
        public DateTime BorrowedAt { get; set; }
        public DateTime DueDate { get; set; }
        public int DaysLeft { get; set; }
    }
}
