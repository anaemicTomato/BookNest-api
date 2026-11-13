namespace BookNest.Settings
{
    public class LoanSettings
    {
        public int LoanDays { get; set; } = 14;
        public decimal FineRatePerDay { get; set; } = 5.00m;
        public int MaxActiveLoans { get; set; } = 5;
    }
}
