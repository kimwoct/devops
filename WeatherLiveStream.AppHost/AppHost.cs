var builder = DistributedApplication.CreateBuilder(args);

builder.AddProject<Projects.WeatherLiveStream_App>("weather-live-stream")
    .WithEnvironment("ASPNETCORE_ENVIRONMENT", "Development")
    .WithEnvironment("OTEL_SERVICE_NAME", Environment.GetEnvironmentVariable("OTEL_SERVICE_NAME") ?? "weather-live-stream-aspire")
    .WithEnvironment("OTEL_EXPORTER_OTLP_ENDPOINT", Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT") ?? string.Empty)
    .WithEnvironment("Redis__ConnectionString", Environment.GetEnvironmentVariable("WEATHER_REDIS_CONNECTION_STRING") ?? "redis-master.data.svc.cluster.local:6379")
    .WithEnvironment("Kafka__BootstrapServers", Environment.GetEnvironmentVariable("WEATHER_KAFKA_BOOTSTRAP_SERVERS") ?? "redpanda.streaming.svc.cluster.local:9093")
    .WithEnvironment("Weather__Topic", Environment.GetEnvironmentVariable("WEATHER_TOPIC") ?? "weather.observations");

builder.Build().Run();
