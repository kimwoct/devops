using Microsoft.AspNetCore.HttpOverrides;
using WeatherLiveStream.App;

var builder = WebApplication.CreateBuilder(args);
var reverseProxyEnabled = builder.Configuration.GetValue("ReverseProxy:Enabled", false);

// Add services to the container.
builder.Services.AddRazorPages();
builder.Services.AddSingleton<LocalWeatherService>();

if (reverseProxyEnabled)
{
    builder.Services.Configure<ForwardedHeadersOptions>(options =>
    {
        options.ForwardedHeaders =
            ForwardedHeaders.XForwardedFor |
            ForwardedHeaders.XForwardedHost |
            ForwardedHeaders.XForwardedProto;

        options.KnownIPNetworks.Clear();
        options.KnownProxies.Clear();
    });
}

var app = builder.Build();

// Configure the HTTP request pipeline.
if (reverseProxyEnabled)
{
    app.UseForwardedHeaders();
}

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

if (!reverseProxyEnabled)
{
    app.UseHttpsRedirection();
}

app.UseRouting();

app.UseAuthorization();

app.MapStaticAssets();
app.MapGet("/weather/local", (LocalWeatherService weather) => weather.GetReport());
app.MapRazorPages()
   .WithStaticAssets();

app.Run();
