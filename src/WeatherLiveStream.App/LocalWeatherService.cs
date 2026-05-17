namespace WeatherLiveStream.App;

public sealed class LocalWeatherService(IConfiguration configuration)
{
    private static readonly string[] Summaries =
    [
        "Clear",
        "Partly cloudy",
        "Cloudy",
        "Light breeze",
        "Light rain"
    ];

    public LocalWeatherReport GetReport()
    {
        var now = DateTimeOffset.Now;
        var location = configuration["Weather:Location"] ?? "Local development";
        var seed = Math.Abs(HashCode.Combine(now.Date, location));
        var temperatureC = 18 + seed % 9;
        var summary = Summaries[seed % Summaries.Length];

        return new LocalWeatherReport(
            location,
            now,
            temperatureC,
            ToFahrenheit(temperatureC),
            55 + seed % 25,
            6 + seed % 18,
            summary,
            "Local generated sample",
            BuildForecast(now.Date, seed));
    }

    private static IReadOnlyList<LocalWeatherForecast> BuildForecast(DateTime today, int seed)
    {
        return Enumerable.Range(0, 5)
            .Select(day =>
            {
                var temperatureC = 17 + (seed + day * 3) % 11;

                return new LocalWeatherForecast(
                    DateOnly.FromDateTime(today.AddDays(day)),
                    temperatureC,
                    ToFahrenheit(temperatureC),
                    Summaries[(seed + day) % Summaries.Length]);
            })
            .ToArray();
    }

    private static int ToFahrenheit(int temperatureC)
    {
        return 32 + (int)Math.Round(temperatureC / 0.5556);
    }
}

public sealed record LocalWeatherReport(
    string Location,
    DateTimeOffset ObservedAt,
    int TemperatureC,
    int TemperatureF,
    int HumidityPercent,
    int WindKph,
    string Summary,
    string Source,
    IReadOnlyList<LocalWeatherForecast> Forecast);

public sealed record LocalWeatherForecast(
    DateOnly Date,
    int TemperatureC,
    int TemperatureF,
    string Summary);
