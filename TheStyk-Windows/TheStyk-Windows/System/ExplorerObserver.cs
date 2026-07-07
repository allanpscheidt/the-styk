using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Threading;

namespace TheStyk.SystemIntegration
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;

        public int Width => Right - Left;
        public int Height => Bottom - Top;

        public override bool Equals(object? obj)
        {
            if (obj is RECT other)
            {
                return Left == other.Left && Top == other.Top && Right == other.Right && Bottom == other.Bottom;
            }
            return false;
        }

        public override int GetHashCode()
        {
            return HashCode.Combine(Left, Top, Right, Bottom);
        }
    }

    public class ExplorerObserver
    {
        public delegate void FolderChangedHandler(string? folderPath, RECT? windowBounds);
        public event FolderChangedHandler? Change;

        private readonly DispatcherTimer _timer;
        private string? _currentFolder;
        private RECT? _currentBounds;
        private IntPtr _lastHwnd = IntPtr.Zero;
        private readonly uint _ownProcessId;

        public string? CurrentFolder => _currentFolder;
        public RECT? CurrentBounds => _currentBounds;

        public ExplorerObserver()
        {
            _ownProcessId = (uint)Environment.ProcessId;

            _timer = new DispatcherTimer(DispatcherPriority.Background)
            {
                Interval = TimeSpan.FromMilliseconds(800)
            };
            _timer.Tick += Timer_Tick;
        }

        public void Start()
        {
            _timer.Start();
            Poll(); // Poll imediato no boot
        }

        public void Stop()
        {
            _timer.Stop();
        }

        private void Timer_Tick(object? sender, EventArgs e)
        {
            Poll();
        }

        public static void Log(string message)
        {
            try
            {
                string logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "The Styk");
                Directory.CreateDirectory(logDir);
                string logPath = Path.Combine(logDir, "debug.log");
                File.AppendAllText(logPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}\r\n");
            }
            catch {}
        }

        private void Poll()
        {
            IntPtr foregroundHwnd = GetForegroundWindow();
            if (foregroundHwnd == IntPtr.Zero)
            {
                ClearFolderState();
                return;
            }

            // Descobre o ID do processo da janela frontal
            GetWindowThreadProcessId(foregroundHwnd, out uint processId);
            string className = GetWindowClassName(foregroundHwnd);

            // Se a janela ativa for o nosso próprio aplicativo, ou a Barra de Tarefas do Windows,
            // ou a janela de ícones ocultos, ou o menu de contexto do Windows, mantemos o estado atual.
            // Isso evita que as notas sumam quando o usuário abre menus da bandeja do The Styk.
            if (processId == _ownProcessId || 
                className == "Shell_TrayWnd" || 
                className == "Shell_SecondaryTrayWnd" || 
                className == "NotifyIconOverflowWindow" ||
                className == "TopLevelWindowForOverflowXamlIsland" ||
                className == "Windows.UI.Core.CoreWindow" ||
                className == "#32770")
            {
                return;
            }

            bool isExplorer = className == "CabinetWClass" || className == "ExploreWClass";
            Log($"Foreground Window: HWND={foregroundHwnd.ToInt64()}, Class={className}, PID={processId}, isExplorer={isExplorer}");

            if (!isExplorer)
            {
                ClearFolderState();
                return;
            }

            // É uma janela do Explorer! Captura caminho e limites (bounds)
            string? path = GetExplorerPath(foregroundHwnd);
            Log($"GetExplorerPath returned: '{path ?? "null"}'");
            
            if (string.IsNullOrEmpty(path))
            {
                ClearFolderState();
                return;
            }

            RECT rect;
            if (GetWindowRect(foregroundHwnd, out rect))
            {
                // Se mudou de pasta ou a janela moveu/redimensionou, atualiza
                if (path != _currentFolder || !_currentBounds.HasValue || !rect.Equals(_currentBounds.Value))
                {
                    _currentFolder = path;
                    _currentBounds = rect;
                    _lastHwnd = foregroundHwnd;

                    Change?.Invoke(_currentFolder, _currentBounds);
                }
            }
        }

        private void ClearFolderState()
        {
            if (_currentFolder != null || _currentBounds != null)
            {
                _currentFolder = null;
                _currentBounds = null;
                _lastHwnd = IntPtr.Zero;
                Change?.Invoke(null, null);
            }
        }

        private static string GetWindowClassName(IntPtr hwnd)
        {
            var builder = new StringBuilder(256);
            GetClassName(hwnd, builder, builder.Capacity);
            return builder.ToString();
        }

        private static string? GetExplorerPath(IntPtr hwnd)
        {
            try
            {
                // Obtenha o tipo COM para ShellWindows
                Type? shellWindowsType = Type.GetTypeFromProgID("Shell.Application");
                if (shellWindowsType == null)
                {
                    Log("Erro: Nao foi possivel obter o ProgID Shell.Application");
                    return null;
                }

                dynamic shellApplication = Activator.CreateInstance(shellWindowsType)!;
                dynamic windows = shellApplication.Windows(); // Coleção de janelas abertas

                int count = windows.Count;
                Log($"Total de janelas COM abertas (ShellWindows): {count}");

                for (int i = 0; i < count; i++)
                {
                    try
                    {
                        dynamic window = windows.Item(i);
                        if (window != null)
                        {
                            long windowHwnd = Convert.ToInt64(window.HWND);
                            IntPtr topLevelHwnd = GetAncestor((IntPtr)windowHwnd, 2); // 2 = GA_ROOT (Pega a janela principal)
                            
                            Log($"Janela COM index={i}: HWND={windowHwnd}, RootAncestor={topLevelHwnd.ToInt64()}, Target={hwnd.ToInt64()}");

                            if (topLevelHwnd == hwnd || windowHwnd == hwnd.ToInt64())
                            {
                                dynamic document = window.Document;
                                if (document != null)
                                {
                                    // Janelas do Explorer têm um objeto Folder no Document
                                    dynamic folder = document.Folder;
                                    if (folder != null)
                                    {
                                        string folderPath = folder.Self.Path;
                                        Log($"Caminho detectado na janela COM index={i}: {folderPath}");
                                        if (!string.IsNullOrEmpty(folderPath) && Path.IsPathRooted(folderPath))
                                        {
                                            return Models.NoteStore.NormalizePath(folderPath);
                                        }
                                    }
                                    else
                                    {
                                        Log($"Janela COM index={i} nao possui Folder no Document");
                                    }
                                }
                                else
                                {
                                    Log($"Janela COM index={i} nao possui Document");
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Log($"Erro ao processar janela COM no index {i}: {ex.Message}");
                    }
                }
            }
            catch (Exception ex)
            {
                Log($"Erro geral ao consultar COM do Explorer: {ex.Message}\n{ex.StackTrace}");
            }
            return null;
        }

        // Win32 API Imports
        [DllImport("user32.dll")]
        private static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    }
}
