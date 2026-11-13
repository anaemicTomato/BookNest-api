namespace BookNest.DTOs
{
    public class FineRowDTO
    {
        public int FineId { get; set; }
        public string Title { get; set; }
        public decimal Amount { get; set; }
        public int DaysLate { get; set; }
    }
}
