using System.Buffers.Binary;
using System.Text.Json;
using Monk.Core;

namespace Monk.BrowserHost;

internal static class Program
{
    private const int MaximumMessageBytes = 64 * 1024;

    private static int Main()
    {
        try
        {
            using var input = Console.OpenStandardInput();
            using var output = Console.OpenStandardOutput();
            var request = ReadMessage(input);
            if (request is null)
            {
                return 0;
            }

            using (request)
            {
                var policy = new StateStore().LoadBrowserPolicy();
                WriteMessage(output, new
                {
                    type = "policy",
                    enforcing = policy.Enforcing,
                    allowedDomains = policy.AllowedDomains,
                    revision = policy.Revision
                });
            }
            return 0;
        }
        catch (Exception exception) when (exception is IOException or JsonException or UnauthorizedAccessException)
        {
            return 1;
        }
    }

    private static JsonDocument? ReadMessage(Stream input)
    {
        Span<byte> header = stackalloc byte[4];
        if (!ReadExactly(input, header))
        {
            return null;
        }

        var length = BinaryPrimitives.ReadInt32LittleEndian(header);
        if (length is <= 0 or > MaximumMessageBytes)
        {
            throw new IOException("Invalid native-messaging request length.");
        }

        var payload = new byte[length];
        if (!ReadExactly(input, payload))
        {
            throw new IOException("Incomplete native-messaging request.");
        }
        return JsonDocument.Parse(payload);
    }

    private static void WriteMessage(Stream output, object response)
    {
        var payload = JsonSerializer.SerializeToUtf8Bytes(response, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Span<byte> header = stackalloc byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(header, payload.Length);
        output.Write(header);
        output.Write(payload);
        output.Flush();
    }

    private static bool ReadExactly(Stream stream, Span<byte> buffer)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var count = stream.Read(buffer[offset..]);
            if (count == 0)
            {
                return false;
            }
            offset += count;
        }
        return true;
    }
}
