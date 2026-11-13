namespace BookNest.DTOs
{
    public class BookListItemDTO
    {
        public int Id { get; set; }
        public string Title { get; set; }
        public string Author { get; set; }
        public string Category { get; set; }
        public int AvailableCopies { get; set; }
    }
}
