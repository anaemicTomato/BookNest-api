namespace BookNest.DTOs
{
    public class HistoryRowDTO
    {
        public int LoanId { get; set; }
        public int Id { get; set; }
        public string Title { get; set; }
        public string Author { get; set; }
        public DateTime BorrowedAt { get; set; }
        public DateTime ReturnedAt { get; set; }
        public bool WasLate { get; set; }
    }
}
