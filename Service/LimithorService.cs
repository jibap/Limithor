using System.Runtime.InteropServices;
using System.ServiceProcess;
using System.Text.Json;
using System.Globalization;
using System.Management;

namespace App.WindowsService
{
    public class LimithorService : ServiceBase
    {
        private readonly string _installPath;
        private readonly string _configPath;
        private readonly UserManager _userManager;
        private Timer? _timer;

        // Dictionnaire pour suivre l'état verrouillé/déverrouillé par session
        private readonly Dictionary<string,bool> _userLocked = new();

        public LimithorService()
        {
            ServiceName = "LimithorService";
            CanHandleSessionChangeEvent = true;
            CanStop = true;

            _installPath = AppDomain.CurrentDomain.BaseDirectory;
            _configPath = Path.Combine(_installPath, "config.json");
            _userManager = new UserManager(_configPath);
            _userManager.Load();
        }

        protected override void OnStart(string[] args)
        {
            WriteLog("Service démarré");

            // Timer pour exécuter Check toutes les 10 secondes
            _timer = new Timer(_ => Check(), null, TimeSpan.Zero, TimeSpan.FromSeconds(10));
            // Vérifier les utilisateurs au démarrage
            SyncUsers();
        }

        protected override void OnStop()
        {
            _timer?.Dispose();
            // Vérifier les utilisateurs à l'arrêt (mode config)
            SyncUsers();
            WriteLog("Service arrêté");
        }

        protected override void OnSessionChange(SessionChangeDescription change)
        {
            string? username = GetSessionInfo(change.SessionId, NativeMethods.WTS_INFO_CLASS.WTSUserName);
            if (string.IsNullOrEmpty(username)) return;

            switch (change.Reason)
            {
                case SessionChangeReason.SessionLock:
                    _userLocked[username] = true;
                    WriteLog($"[{username}] verrouillée");
                    break;

                case SessionChangeReason.SessionUnlock:
                    _userLocked[username] = false;
                    WriteLog($"[{username}] déverrouillée");
                    break;
            }
        }

        private void Check()
        {
            bool configHasChanged = false;

            foreach (var kvp in _userManager.Config.users)
            {
                string username = kvp.Key;
                var user = kvp.Value;

                if (!user.config.enabled) continue;

                int? sessionId = GetActiveSessionId(username);
                // session déconnectée → on ignore
                if (sessionId == null) continue; 

                // Ignore si la session est verrouillée
                if (_userLocked.TryGetValue(username, out bool isLocked) && isLocked)
                    continue;

                bool userChanged = false;

                string currentCycleKey = GetCycleKey(user.config.limitType);
                if (user.state.cycleKey != currentCycleKey)
                {
                    if (!string.IsNullOrEmpty(user.state.cycleKey))
                    {
                        var usedDurationBeforeReset = user.state.usedDuration;
                        if (user.config.reportMode)
                        {
                            var remainingTime = user.state.usedDuration - user.config.limitDuration; // calcul le temps non utilisé ou sur-utilisé
                            int bonusCap = user.config.limitDuration * 4; // Autorise jusqu'à 4x la valeur du quota en bonus
                            int malusCap = user.config.limitDuration; // Tronque la valeur du malus à 1x le quota
                            user.state.usedDuration = Math.Clamp(remainingTime, -bonusCap, malusCap);
                        }
                        else
                        {
                            user.state.usedDuration = 0;
                        }
                        WriteLog($"RAZ pour [{username}] : {user.state.cycleKey} = {usedDurationBeforeReset} mins.");
                    }
                    user.state.cycleKey = currentCycleKey;
                    userChanged = true;
                }

                // Compter une minute
                long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                var last = user.state.lastCountedTimestamp;
                if (last == 0 || now - last >= 60)
                {
                    user.state.usedDuration += 1;
                    user.state.lastCountedTimestamp = now;
                    userChanged = true;
                    WriteLog($"1 minute comptée pour [{username}], total sur la période : {user.state.usedDuration} mins.");
                }

                if (userChanged)
                    configHasChanged = true;

                // Déconnexion si pas en mode chrono && quota dépassé
                if (!user.config.chronoMode && user.state.usedDuration >= user.config.limitDuration)
                {
                    WriteLog($"{username} a dépassé son quota. Déconnexion...");
                    NativeMethods.WTSDisconnectSession(IntPtr.Zero, sessionId.Value, false);
                }
            }

            if (configHasChanged)
                _userManager.Save();
        }

        private void SyncUsers()
        {
            bool changed = _userManager.SyncUsers();
            if (changed)
            {
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
            if (!_userManager.Config.log) return;

            File.AppendAllText(
                Path.Combine(_installPath, "service.log"),
                $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} - {message}{Environment.NewLine}"
            );
        }

        private int? GetActiveSessionId(string username)
        {
            uint sessionId = NativeMethods.WTSGetActiveConsoleSessionId();
            if (sessionId == 0xFFFFFFFF) return null;

            IntPtr buffer;
            int bytesReturned;
            if (NativeMethods.WTSQuerySessionInformation(IntPtr.Zero, (int)sessionId,
                NativeMethods.WTS_INFO_CLASS.WTSConnectState, out buffer, out bytesReturned))
            {
                var state = (NativeMethods.WTS_CONNECTSTATE_CLASS)Marshal.ReadInt32(buffer);
                NativeMethods.WTSFreeMemory(buffer);

                if (state != NativeMethods.WTS_CONNECTSTATE_CLASS.WTSActive)
                    return null;
            }

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

        // Pour exécution en console (debug / dev)
        public void StartForConsole(string[] args) => OnStart(args);
        public void StopForConsole() => OnStop();
    }

    internal static class NativeMethods
    {
        [DllImport("Wtsapi32.dll", SetLastError = true)]
        public static extern bool WTSDisconnectSession(IntPtr hServer, int sessionId, bool bWait);

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

        public enum WTS_INFO_CLASS { WTSUserName = 5, WTSDomainName = 7, WTSConnectState = 8 }
        public enum WTS_CONNECTSTATE_CLASS
        {
            WTSActive, WTSConnected, WTSConnectQuery, WTSShadow, WTSDisconnected,
            WTSIdle, WTSListen, WTSReset, WTSDown, WTSInit
        }
    }

    // --- Classes de configuration ---
    public class UserConfig 
    { 
        public string limitType { get; set; } = "weekly"; 
        public int limitDuration { get; set; } = 480; 
        public bool enabled { get; set; } = true; 
        public bool chronoMode { get; set; } = false; 
        public bool reportMode { get; set; } = false; 
    }

    public class UserState  
    { 
        public int    usedDuration          { get; set; } = 480; // = limitDuration → bloqué par défaut
        public string cycleKey              { get; set; } = $"{DateTime.Now.Year}-w{ISOWeek.GetWeekOfYear(DateTime.Now)}"; 
        public long   lastCountedTimestamp  { get; set; } = DateTimeOffset.UtcNow.ToUnixTimeSeconds(); 
    }    

    public class UserData { public UserConfig config { get; set; } = new(); public UserState state { get; set; } = new(); }
    public class RootConfig { public bool log { get; set; } = false; public Dictionary<string, UserData> users { get; set; } = new(); }

    public class UserManager
    {
        public RootConfig Config { get; private set; } = new();
        private readonly string _configPath;

        public UserManager(string configPath) { _configPath = configPath; }

        public void Load()
        {
            if (!File.Exists(_configPath))
            {
                Config = new RootConfig();
                Save(); 
            }
            else
            {
                try
                {
                    var json = File.ReadAllText(_configPath);
                    Config = JsonSerializer.Deserialize<RootConfig>(json) ?? new RootConfig();
                }
                catch { Config = new RootConfig(); }
            }

            SyncUsers();
            Save();
        }

        public bool SyncUsers()
        {
            var windowsUsers = GetLocalWindowsUsers().ToHashSet(StringComparer.OrdinalIgnoreCase);
            bool changed = false;

            // Ajouter les utilisateurs manquants
            foreach (var user in windowsUsers)
            {
                if (!Config.users.ContainsKey(user))
                {
                    var data = new UserData();
                    if (IsUserAdmin(user))
                    {
                        data.config.enabled = false;
                    }
                    Config.users[user] = data;
                    changed = true;
                }
            }

            // Retirer les utilisateurs supprimés/renommés
            var toRemove = Config.users.Keys
                .Where(u => !windowsUsers.Contains(u))
                .ToList();

            foreach (var u in toRemove)
            {
                Config.users.Remove(u);
                changed = true;
            }

            return changed;
        }

        private bool IsUserAdmin(string username)
        {
            try
            {
                var groupQuery = new ManagementObjectSearcher(
                    "SELECT * FROM Win32_Group WHERE SID='S-1-5-32-544'");

                foreach (var group in groupQuery.Get())
                {
                    string groupName = group["Name"]?.ToString() ?? "";
                    string domain    = group["Domain"]?.ToString() ?? "";

                    var memberQuery = new ManagementObjectSearcher(
                        $"SELECT * FROM Win32_GroupUser WHERE GroupComponent=" +
                        $"\"Win32_Group.Domain='{domain}',Name='{groupName}'\"");

                    foreach (var member in memberQuery.Get())
                    {
                        string part = member["PartComponent"]?.ToString() ?? "";
                        if (part.IndexOf($"Name=\"{username}\"", StringComparison.OrdinalIgnoreCase) >= 0)
                            return true;
                    }
                }
            }
            catch { }
            return false;
        }

        public void Save()
        {
            var json = JsonSerializer.Serialize(Config, new JsonSerializerOptions { WriteIndented = true, PropertyNameCaseInsensitive = true });
            File.WriteAllText(_configPath, json);
        }

        private IEnumerable<string> GetLocalWindowsUsers()
        {
            var users = new List<string>();
            var query = new ManagementObjectSearcher("SELECT Name, Disabled FROM Win32_UserAccount WHERE LocalAccount=True");
            foreach (var obj in query.Get())
            {
                bool disabled = obj["Disabled"] != null && (bool)obj["Disabled"];
                if (!disabled) users.Add(obj["Name"]?.ToString() ?? "");
            }
            return users;
        }
    }

    // --- Programme principal ---
    internal static class Program
    {
        static void Main()
        {
            var service = new LimithorService();

            if (Environment.UserInteractive)
            {
                Console.WriteLine("Service démarré en mode console.");
                service.StartForConsole(new string[0]);
                Console.WriteLine("Appuyez sur [Enter] pour arrêter le service.");
                Console.ReadLine();
                service.StopForConsole();
            }
            else
            {
                ServiceBase.Run(service);
            }
        }
    }
}
