using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using WeatherLiveStream.App;

namespace WeatherLiveStream.App.Pages;

public class IndexModel(LocalWeatherService weatherService) : PageModel
{
    public LocalWeatherReport Weather { get; private set; } = default!;

    public void OnGet()
    {
        Weather = weatherService.GetReport();
    }
}
