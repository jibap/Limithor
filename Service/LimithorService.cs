namespace App.WindowsService;

using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Globalization;
using System.Management;

public sealed class LimithorService
{
    private readonly string _installPath;
    private readonly string _configPath;
    private readonly UserManager _userManager;

    public LimithorService()
    {
        _installPath = AppDomain.CurrentDomain.BaseDirectory;
        _configPath = Path.Combine(_installPath, "config.json");
        _userManager = new UserManager(_configPath);
        _userManager.Load();
    }

    public void Check()
    {
        bool configHasChanged = false;
        WriteLog("Vérification des quotas des utilisateurs...");
        foreach (var kvp in _userManager.Config.users)
        {
            string username = kvp.Key;
            var user = kvp.Value;

            if (!user.config.enabled)
            {
                continue;
            }

            int? sessionId = GetActiveSessionId(username);
            bool isActive = sessionId.HasValue;

            WriteLog($"Utilisateur: {username}, Actif: {isActive}, Durée utilisée: {user.state.usedDuration} mins, Limite: {user.config.limitDuration} mins");

            if (isActive)
            {
                bool userChanged = false;

                // Réinitialiser le cycle si nécessaire
                string currentCycleKey = GetCycleKey(user.config.limitType);
                if (user.state.cycleKey != currentCycleKey)
                {
                    if (!string.IsNullOrEmpty(user.state.cycleKey))
                    {
                        user.state.usedDuration = 0;
                    }
                    user.state.cycleKey = currentCycleKey;
                    userChanged = true;
                    WriteLog($"Cycle réinitialisé pour {username}.");
                }

                // Compter une minute supplémentaire
                long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                var last = user.state.lastCountedTimestamp; 
                if (last == 0 || now - last >= 60)
                {
                    user.state.usedDuration += 1; // 1 minute entamée est comptabilisée
                    user.state.lastCountedTimestamp = now;
                    userChanged = true;
                    WriteLog($"1 minute de + pour {username}, total: {user.state.usedDuration} mins.");
                }

                if (userChanged){
                    configHasChanged = true;
                }

                // Vérifier si l'utilisateur a dépassé son quota
                if (user.state.usedDuration >= user.config.limitDuration)
                {
                    WriteLog($"⛔ Utilisateur {username} a dépassé son quota. Deconnexion...");
                    NativeMethods.WTSDisconnectSession(IntPtr.Zero, sessionId!.Value, false);
                }
            }
        }

        if(configHasChanged)
        {
            // Sauvegarder les modifications uniquement si la congig a changé
            _userManager.Save();
        }
    }

    private string GetCycleKey(string limitType)
    {
        return limitType == "daily"
            ? DateTime.Now.ToString("yyyy-MM-dd")
            : $"{DateTime.Now.Year}-w{ISOWeek.GetWeekOfYear(DateTime.Now)}";

    }

    private void WriteLog(string message)
    {
        if (!_userManager.Config.log)
            return;
        File.AppendAllText(
            Path.Combine(_installPath, "service.log"),
            $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} - {message}{Environment.NewLine}"
        );
    }

    private int? GetActiveSessionId(string username)
    {
        uint sessionId = NativeMethods.WTSGetActiveConsoleSessionId();
        if (sessionId == 0xFFFFFFFF)
            return null;

        // Vérifie l'état de la session
        IntPtr buffer;
        int bytesReturned;
        if (NativeMethods.WTSQuerySessionInformation(
            IntPtr.Zero,
            (int)sessionId,
            NativeMethods.WTS_INFO_CLASS.WTSConnectState,
            out buffer,
            out bytesReturned))
        {
            var state = (NativeMethods.WTS_CONNECTSTATE_CLASS)Marshal.ReadInt32(buffer);
            NativeMethods.WTSFreeMemory(buffer);

            if (state != NativeMethods.WTS_CONNECTSTATE_CLASS.WTSActive)
                return null; // session inactive
        }

        // Vérifie le nom de l'utilisateur
        string? user = GetSessionInfo((int)sessionId, NativeMethods.WTS_INFO_CLASS.WTSUserName);
        if (!string.IsNullOrEmpty(user) && string.Equals(user, username, StringComparison.OrdinalIgnoreCase))
            return (int)sessionId;

        return null;
    }


    private string? GetSessionInfo(int sessionId, NativeMethods.WTS_INFO_CLASS infoClass)
    {
        IntPtr buffer;
        int bytesReturned;
        if (NativeMethods.WTSQuerySessionInformation(IntPtr.Zero, sessionId, infoClass, out buffer, out bytesReturned) && bytesReturned > 1)
        {
            string value = Marshal.PtrToStringAnsi(buffer) ?? "";
            NativeMethods.WTSFreeMemory(buffer);
            return value;
        }
        return null;
    }

}


internal static class NativeMethods
{
    [DllImport("Wtsapi32.dll", SetLastError = true)]
    public static extern bool WTSDisconnectSession(
        IntPtr hServer,
        int sessionId,
        bool bWait
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint WTSGetActiveConsoleSessionId();

    [DllImport("Wtsapi32.dll", SetLastError = true)]
    public static extern bool WTSQuerySessionInformation(
        IntPtr hServer,
        int sessionId,
        WTS_INFO_CLASS wtsInfoClass,
        out IntPtr ppBuffer,
        out int pBytesReturned
    );

    [DllImport("Wtsapi32.dll")]
    public static extern void WTSFreeMemory(IntPtr memory);

    public enum WTS_INFO_CLASS
    {
        WTSUserName = 5,
        WTSDomainName = 7,
        WTSConnectState = 8
    }

    public enum WTS_CONNECTSTATE_CLASS
    {
        WTSActive,
        WTSConnected,
        WTSConnectQuery,
        WTSShadow,
        WTSDisconnected,
        WTSIdle,
        WTSListen,
        WTSReset,
        WTSDown,
        WTSInit
    }
}

public class UserConfig
{
    public string limitType { get; set; } = "weekly";
    public int limitDuration { get; set; } = 480;
    public bool enabled { get; set; } = false;
}

public class UserState
{
    public int usedDuration { get; set; } = 0;
    public string cycleKey { get; set; } = "";
    public long lastCountedTimestamp { get; set; } = 0;
}

public class UserData
{
    public UserConfig config { get; set; } = new UserConfig();
    public UserState state { get; set; } = new UserState();
}

public class RootConfig
{
    public bool log { get; set; } = false;
    public Dictionary<string, UserData> users { get; set; } = new();
}

public class UserManager
{
    public RootConfig Config { get; private set; } = new();
    private readonly string _configPath;

    public UserManager(string configPath)
    {
        _configPath = configPath;
    }

    public void Load()
    {
        if (!File.Exists(_configPath))
        {
            Config = new RootConfig();
            GenerateAllUsers();
            Save();
            return;
        }

        try
        {
            var json = File.ReadAllText(_configPath);
            Config = JsonSerializer.Deserialize<RootConfig>(json) ?? new RootConfig();
        }
        catch
        {
            
        }
    }

    private void GenerateAllUsers()
    {
        foreach (var user in GetLocalWindowsUsers())
        {
            Config.users[user] = new UserData
            {
                config = new UserConfig()
            };
        }
    }

    public void Save()
    {
        var json = JsonSerializer.Serialize(Config, new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNameCaseInsensitive = true
        });
        File.WriteAllText(_configPath, json);
    }

    private IEnumerable<string> GetLocalWindowsUsers()
    {
        var users = new List<string>();
        var query = new ManagementObjectSearcher(
            "SELECT Name, Disabled FROM Win32_UserAccount WHERE LocalAccount=True"
        );

        foreach (var obj in query.Get())
        {
            bool disabled = false;
            if (obj["Disabled"] != null)
                disabled = (bool)obj["Disabled"];

            if (!disabled) // seulement les comptes activés
                users.Add(obj["Name"]?.ToString() ?? "");
        }

        return users;
    }

}