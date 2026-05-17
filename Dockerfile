FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/WeatherLiveStream.App/WeatherLiveStream.App.csproj src/WeatherLiveStream.App/
RUN dotnet restore src/WeatherLiveStream.App/WeatherLiveStream.App.csproj

COPY src/WeatherLiveStream.App/ src/WeatherLiveStream.App/
WORKDIR /src/src/WeatherLiveStream.App
RUN dotnet publish WeatherLiveStream.App.csproj -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "WeatherLiveStream.App.dll"]
