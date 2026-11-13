namespace BookNest.DTOs
{
    public class BookDetailDTO
    {
        public int Id { get; set; }
        public string Title { get; set; }
        public string Author { get; set; }
        public string Isbn { get; set; }
        public string Category { get; set; }
        public int TotalCopies { get; set; }
        public int AvailableCopies { get; set; }
        public bool HasLoan { get; set; }
        public bool HasReservation { get; set; }
        public bool CanBorrow { get; set; }
    }
}
