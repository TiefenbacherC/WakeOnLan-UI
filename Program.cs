// Kleine Weboberfläche für Wake-on-LAN: pro Gerät ein Knopf, der Pi schickt das Magic Packet
// ins lokale Netz. Die Geräte stehen in devices.json und werden bei jedem Aufruf neu gelesen.
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.Json;
using static System.Net.WebUtility;

var builder = WebApplication.CreateBuilder(args);
var port = Environment.GetEnvironmentVariable("PORT") ?? "8090";
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
var app = builder.Build();

var configFile = Environment.GetEnvironmentVariable("WOL_CONFIG") ?? "/config/devices.json";
var version = Environment.GetEnvironmentVariable("VERSION") ?? "dev";
var jsonOptions = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };

List<Device> LoadDevices()
{
    try
    {
        return JsonSerializer.Deserialize<List<Device>>(File.ReadAllText(configFile), jsonOptions) ?? [];
    }
    catch (FileNotFoundException)
    {
        return [];
    }
}

app.MapGet("/", async () => Results.Content(await Render(LoadDevices()), "text/html; charset=utf-8"));

app.MapPost("/wake", async (HttpRequest request) =>
{
    var devices = LoadDevices();
    var form = await request.ReadFormAsync();
    if (!int.TryParse(form["id"], out var id) || id < 0 || id >= devices.Count)
        return Results.Content(await Render(devices, "Unbekanntes Gerät", true), "text/html; charset=utf-8", statusCode: 400);

    var device = devices[id];
    try
    {
        await SendMagicPacket(device);
        return Results.Content(await Render(devices, $"Magic Packet an {device.Name} gesendet."), "text/html; charset=utf-8");
    }
    catch (Exception e) when (e is FormatException or SocketException)
    {
        return Results.Content(await Render(devices, $"Fehler: {e.Message}", true), "text/html; charset=utf-8", statusCode: 500);
    }
});

Console.WriteLine($"WakeOnLan-UI {version} läuft auf Port {port}");
app.Run();

// Magic Packet: 6 × 0xFF, dann 16 × die MAC-Adresse – als UDP-Broadcast an Port 9
static async Task SendMagicPacket(Device device)
{
    var mac = Convert.FromHexString(device.Mac.Replace(":", "").Replace("-", ""));
    if (mac.Length != 6) throw new FormatException($"Ungültige MAC-Adresse: {device.Mac}");

    var packet = new byte[6 + 16 * 6];
    Array.Fill(packet, (byte)0xFF, 0, 6);
    for (var i = 0; i < 16; i++) mac.CopyTo(packet, 6 + i * 6);

    var target = IPAddress.Parse(string.IsNullOrEmpty(device.Broadcast) ? "255.255.255.255" : device.Broadcast);
    using var udp = new UdpClient { EnableBroadcast = true };
    await udp.SendAsync(packet, new IPEndPoint(target, 9));
}

static async Task<bool?> IsOnline(string? ip)
{
    if (string.IsNullOrEmpty(ip)) return null;
    try
    {
        using var ping = new Ping();
        return (await ping.SendPingAsync(ip, 1000)).Status == IPStatus.Success;
    }
    catch (PingException)
    {
        return false;
    }
}

async Task<string> Render(List<Device> devices, string? message = null, bool error = false)
{
    var online = await Task.WhenAll(devices.Select(d => IsOnline(d.Ip)));
    var rows = devices.Select((d, i) =>
    {
        var status = online[i] switch
        {
            true => "<span class=\"on\">● online</span>",
            false => "<span class=\"off\">● offline</span>",
            null => "",
        };
        return $"""
            <form class="dev" method="post" action="/wake">
              <div><div class="name">{HtmlEncode(d.Name)}</div><div class="sub">{HtmlEncode(d.Mac)} {status}</div></div>
              <input type="hidden" name="id" value="{i}"><button>Aufwecken</button>
            </form>
            """;
    });
    var list = devices.Count > 0 ? string.Join("\n", rows) : $"<p>Keine Geräte in {HtmlEncode(configFile)}.</p>";
    var msg = message is null ? "" : $"<div class=\"msg{(error ? " err" : "")}\">{HtmlEncode(message)}</div>";

    return $$"""
        <!doctype html>
        <html lang="de"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Wake on LAN</title>
        <style>
          body { font-family: system-ui, sans-serif; background: #f4f4f5; color: #18181b; margin: 0; padding: 16px; }
          main { max-width: 480px; margin: 0 auto; }
          .msg { padding: 12px; border-radius: 8px; margin-bottom: 16px; background: #dcfce7; }
          .msg.err { background: #fee2e2; }
          .dev { background: #fff; border-radius: 12px; padding: 16px; margin-bottom: 12px; display: flex;
                 align-items: center; justify-content: space-between; gap: 12px; box-shadow: 0 1px 3px #0001; }
          .name { font-weight: 600; }
          .sub { font-size: 13px; color: #71717a; }
          .on { color: #16a34a; } .off { color: #a1a1aa; }
          button { font-size: 16px; padding: 10px 18px; border: 0; border-radius: 8px; background: #2563eb; color: #fff; cursor: pointer; }
          footer { font-size: 12px; color: #a1a1aa; margin-top: 24px; }
          @media (prefers-color-scheme: dark) {
            body { background: #18181b; color: #f4f4f5; }
            .dev { background: #27272a; }
            .msg { background: #14532d; } .msg.err { background: #7f1d1d; }
          }
        </style></head>
        <body><main>
        <h1>Wake on LAN</h1>
        {{msg}}
        {{list}}
        <footer>{{HtmlEncode(version)}}</footer>
        </main></body></html>
        """;
}

record Device(string Name, string Mac, string? Ip, string? Broadcast);
