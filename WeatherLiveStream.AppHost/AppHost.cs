var builder = DistributedApplication.CreateBuilder(args);

builder.AddProject<Projects.WeatherLiveStream_App>("weather-live-stream")
    .WithEnvironment("ASPNETCORE_ENVIRONMENT", "Development")
    .WithEnvironment("Redis__ConnectionString", "redis-master.data.svc.cluster.local:6379")
    .WithEnvironment("Kafka__BootstrapServers", "redpanda.streaming.svc.cluster.local:9093")
    .WithEnvironment("Weather__Topic", "weather.observations");

builder.Build().Run();
