using System.ComponentModel;
using System.Net;
using System.Runtime.InteropServices;

namespace Harbor.Desktop;

internal sealed record LocalTcpConnection(int ProcessId, int State, int RemotePort, string Remote, string Local);

internal static class LocalTcpConnections
{
    [DllImport("iphlpapi.dll", SetLastError = true)]
    private static extern uint GetExtendedTcpTable(IntPtr table, ref uint size, [MarshalAs(UnmanagedType.Bool)] bool sorted, uint family, uint tableClass, uint reserved);

    internal static IReadOnlyList<LocalTcpConnection> Read()
    {
        var result = new List<LocalTcpConnection>();
        foreach (var family in new uint[] { 2, 23 })
        {
            uint size = 0;
            var status = GetExtendedTcpTable(IntPtr.Zero, ref size, false, family, 5, 0);
            if (status != 0 && status != 122) throw new Win32Exception((int)status);
            for (var attempt = 0; attempt < 3; attempt++)
            {
                var table = Marshal.AllocHGlobal(checked((int)size));
                try
                {
                    status = GetExtendedTcpTable(table, ref size, false, family, 5, 0);
                    if (status == 122) continue;
                    if (status != 0) throw new Win32Exception((int)status);
                    var count = Marshal.ReadInt32(table);
                    var stride = family == 2 ? 24 : 56;
                    for (var i = 0; i < count; i++)
                    {
                        var row = IntPtr.Add(table, 4 + i * stride);
                        var state = Marshal.ReadInt32(row, family == 2 ? 0 : 48);
                        if (state != 2 && state != 5) continue; // LISTEN / ESTABLISHED
                        int Port(int offset) => (Marshal.ReadByte(row, offset) << 8) | Marshal.ReadByte(row, offset + 1);
                        string Address(int offset, int scopeOffset)
                        {
                            var bytes = new byte[family == 2 ? 4 : 16];
                            Marshal.Copy(IntPtr.Add(row, offset), bytes, 0, bytes.Length);
                            return family == 2 ? new IPAddress(bytes).ToString() : $"[{new IPAddress(bytes, unchecked((uint)Marshal.ReadInt32(row, scopeOffset)))}]";
                        }
                        var remotePort = Port(family == 2 ? 16 : 44);
                        result.Add(new LocalTcpConnection(Marshal.ReadInt32(row, family == 2 ? 20 : 52), state, remotePort,
                            $"{Address(family == 2 ? 12 : 24, 40)}:{remotePort}", $"{Address(family == 2 ? 4 : 0, 16)}:{Port(family == 2 ? 8 : 20)}"));
                    }
                    break;
                }
                finally { Marshal.FreeHGlobal(table); }
            }
        }
        return result;
    }
}
