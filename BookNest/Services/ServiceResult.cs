namespace BookNest.Services
{
    public class ServiceResult
    {
        public bool Success { get; set; }
        public int StatusCode { get; set; }
        public string? Message { get; set; }
        public object? Data { get; set; }

        public ServiceResult(bool success, int statusCode, string? message = null, object? data = null)
        {
            Success = success;
            StatusCode = statusCode;
            Message = message;
            Data = data;
        }

        public static ServiceResult Ok(object data)
        {
            return new ServiceResult(true, 200, null, data);
        }

        public static ServiceResult Fail(int statusCode, string message)
        {
            return new ServiceResult(false, statusCode, message);
        }
    }
}
