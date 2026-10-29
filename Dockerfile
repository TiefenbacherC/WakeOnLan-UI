FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY WakeOnLanUi.csproj ./
RUN dotnet restore
COPY Program.cs ./
RUN dotnet publish -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app ./
ARG VERSION=dev
ENV VERSION=$VERSION
# läuft als root, damit Ping (Online-Anzeige) Raw-Sockets öffnen darf
CMD ["dotnet", "WakeOnLanUi.dll"]
