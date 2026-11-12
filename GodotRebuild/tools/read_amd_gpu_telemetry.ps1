<#
Read-only AMD PMLog telemetry. Uses the existing 64-bit system ADL driver DLL.
No setters, PMLog start/stop, tuning, registry writes, installation or GUI.
Official ABI and units:
https://github.com/GPUOpen-LibrariesAndSDKs/display-library/blob/master/include/adl_structures.h
https://github.com/GPUOpen-LibrariesAndSDKs/display-library/blob/master/include/adl_defines.h
https://gpuopen-librariesandsdks.github.io/adl/group__OVERDRIVE8API.html
This is device-wide telemetry, NOT a per-process utilization/power counter.
Example: .\tools\read_amd_gpu_telemetry.ps1 -Samples 30 -IntervalMs 1000 -OutputJson .\Builds\amd-pmlog.json
#>
[CmdletBinding()]
param(
    [ValidateRange(1,240)][int]$Samples = 5,
    [ValidateRange(100,1000)][int]$IntervalMs = 1000,
    [string]$OutputJson = ''
)
$ErrorActionPreference = 'Stop'
if (-not [Environment]::Is64BitProcess) { throw 'Run with 64-bit PowerShell; no 32-bit driver fallback is attempted.' }
if (-not ('KDTD.ReadOnlyAmdAdl' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace KDTD {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
    public struct AdlAdapterInfo {
        public int Size, Index;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string Udid;
        public int Bus, Device, Function, Vendor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string Name;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string Display;
        public int Present, Exist;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string DriverPath;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string DriverPathExt;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string Pnp;
        public int OsDisplayIndex;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct AdlSensor { public int Supported, Value; }
    [StructLayout(LayoutKind.Sequential)]
    public struct AdlPmLog {
        public int Size;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=256)] public AdlSensor[] Sensors;
    }
    public sealed class ReadOnlyAmdAdl : IDisposable {
        private const string Dll = @"C:\Windows\System32\atiadlxx.dll";
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate IntPtr Allocate(int bytes);
        [DllImport(Dll, CallingConvention=CallingConvention.Cdecl, ExactSpelling=true)]
        private static extern int ADL2_Main_Control_Create(Allocate callback, int connected, out IntPtr context);
        [DllImport(Dll, CallingConvention=CallingConvention.Cdecl, ExactSpelling=true)]
        private static extern int ADL2_Main_Control_Destroy(IntPtr context);
        [DllImport(Dll, CallingConvention=CallingConvention.Cdecl, ExactSpelling=true)]
        private static extern int ADL2_Adapter_NumberOfAdapters_Get(IntPtr context, out int count);
        [DllImport(Dll, CallingConvention=CallingConvention.Cdecl, ExactSpelling=true)]
        private static extern int ADL2_Adapter_AdapterInfo_Get(IntPtr context, IntPtr info, int bytes);
        [DllImport(Dll, CallingConvention=CallingConvention.Cdecl, ExactSpelling=true)]
        private static extern int ADL2_New_QueryPMLogData_Get(IntPtr context, int adapter, ref AdlPmLog output);
        private readonly Allocate allocator = delegate(int bytes) { return Marshal.AllocHGlobal(bytes); };
        private IntPtr context;
        public readonly List<AdlAdapterInfo> Adapters = new List<AdlAdapterInfo>();
        private static void Check(int code, string api) {
            if (code != 0) throw new InvalidOperationException(api + " returned ADL code " + code);
        }
        public ReadOnlyAmdAdl() {
            if (Marshal.SizeOf(typeof(AdlAdapterInfo)) != 1572 || Marshal.SizeOf(typeof(AdlPmLog)) != 2052)
                throw new InvalidOperationException("Unexpected ADL ABI layout.");
            Check(ADL2_Main_Control_Create(allocator, 1, out context), "ADL2_Main_Control_Create");
            try {
                int count;
                Check(ADL2_Adapter_NumberOfAdapters_Get(context, out count), "ADL2_Adapter_NumberOfAdapters_Get");
                if (count < 1 || count > 250) throw new InvalidOperationException("Unexpected adapter count " + count);
                int size = Marshal.SizeOf(typeof(AdlAdapterInfo));
                IntPtr buffer = Marshal.AllocHGlobal(size * count);
                try {
                    for (int n=0; n<count; n++) {
                        IntPtr ptr = IntPtr.Add(buffer, n*size);
                        for (int k=0; k<size; k+=4) Marshal.WriteInt32(ptr, k, 0);
                        Marshal.WriteInt32(ptr, size);
                    }
                    Check(ADL2_Adapter_AdapterInfo_Get(context, buffer, size * count), "ADL2_Adapter_AdapterInfo_Get");
                    // ADL exposes display aliases of one physical PCI adapter.
                    var seen = new HashSet<string>();
                    for (int n=0; n<count; n++) {
                        var info = (AdlAdapterInfo)Marshal.PtrToStructure(IntPtr.Add(buffer, n*size), typeof(AdlAdapterInfo));
                        string pci = info.Bus + ":" + info.Device + ":" + info.Function + ":" + info.Vendor;
                        if (info.Present != 0 && info.Name != null && info.Name.IndexOf("Radeon", StringComparison.OrdinalIgnoreCase) >= 0 && seen.Add(pci))
                            Adapters.Add(info);
                    }
                } finally { Marshal.FreeHGlobal(buffer); }
            } catch { Dispose(); throw; }
        }
        public AdlPmLog Read(int adapter) {
            if (context == IntPtr.Zero) throw new ObjectDisposedException("ReadOnlyAmdAdl");
            var output = new AdlPmLog { Size = Marshal.SizeOf(typeof(AdlPmLog)), Sensors = new AdlSensor[256] };
            Check(ADL2_New_QueryPMLogData_Get(context, adapter, ref output), "ADL2_New_QueryPMLogData_Get");
            return output;
        }
        public void Dispose() {
            if (context != IntPtr.Zero) { ADL2_Main_Control_Destroy(context); context = IntPtr.Zero; }
            GC.KeepAlive(allocator);
        }
    }
}
'@
}
$sensorMap = [ordered]@{
    gfx_clock_mhz = 1; memory_clock_mhz = 2; edge_temperature_c = 8
    fan_rpm = 14; gfx_activity_percent = 19; memory_activity_percent = 20
    gfx_voltage_mv = 21; asic_power_w = 23; hotspot_temperature_c = 27
    gfx_power_w = 30; throttler_status = 35; board_power_w = 73
}
$result = [ordered]@{
    schema = 1
    source = 'ADL2_New_QueryPMLogData_Get'
    scope = 'device-wide; not attributable to a process'
    read_only = $true
    dll = 'C:\Windows\System32\atiadlxx.dll'
    dll_version = (Get-Item -LiteralPath 'C:\Windows\System32\atiadlxx.dll').VersionInfo.FileVersion
    interval_ms = $IntervalMs
    requested_samples = $Samples
    adapters = @()
    samples = @()
    errors = @()
}
$probe = $null
try {
    $probe = [KDTD.ReadOnlyAmdAdl]::new()
    $result.adapters = @($probe.Adapters | ForEach-Object {
        [ordered]@{ index=$_.Index; name=$_.Name; bus=$_.Bus; device=$_.Device; function=$_.Function; pnp=$_.Pnp }
    })
    if ($probe.Adapters.Count -eq 0) { throw 'No present AMD Radeon ADL adapter found.' }
    for ($sample=0; $sample -lt $Samples; $sample++) {
        foreach ($adapter in $probe.Adapters) {
            $data = $probe.Read($adapter.Index)
            $row = [ordered]@{ timestamp_utc=[DateTime]::UtcNow.ToString('o'); adapter_index=$adapter.Index }
            $supported = @()
            foreach ($name in $sensorMap.Keys) {
                $sensor = $data.Sensors[$sensorMap[$name]]
                $row[$name] = if ($sensor.Supported -ne 0) { $sensor.Value } else { $null }
                if ($sensor.Supported -ne 0) { $supported += $name }
            }
            $row['supported_sensors'] = $supported
            $result.samples += $row
        }
        if ($sample + 1 -lt $Samples) { Start-Sleep -Milliseconds $IntervalMs }
    }
} catch { $result.errors += $_.Exception.ToString() }
finally { if ($null -ne $probe) { $probe.Dispose() } }
$json = $result | ConvertTo-Json -Depth 8
if ($OutputJson) {
    $absolute = [IO.Path]::GetFullPath($OutputJson)
    [IO.File]::WriteAllText($absolute, $json, [Text.UTF8Encoding]::new($false))
}
$json
if ($result.errors.Count -gt 0) { exit 1 }
