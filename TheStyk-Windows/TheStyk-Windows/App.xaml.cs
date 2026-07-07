using System;
using System.IO;
using System.IO.Pipes;
using System.Threading;
using System.Windows;
using TheStyk.SystemIntegration;
using TheStyk.UI;
using Application = System.Windows.Application;
using MessageBox = System.Windows.MessageBox;

namespace TheStyk
{
    public partial class App : Application
    {
        private ExplorerObserver? _observer;
        private TrayController? _trayController;

        private static Mutex? _mutex;
        private const string MutexName = "TheStykSingleInstanceMutex";
        private const string PipeName = "TheStykIPCPipe";

        private void Application_Startup(object sender, StartupEventArgs e)
        {
            bool createdNew;
            _mutex = new Mutex(true, MutexName, out createdNew);

            string[] args = e.Args;
            if (args.Length >= 2 && args[0] == "-create")
            {
                string folder = args[1];
                if (!createdNew)
                {
                    // Envia o caminho da pasta para a instância já ativa e encerra a atual
                    SendIPCCommand(folder);
                    Shutdown();
                    return;
                }
                else
                {
                    // Se não estava rodando, inicia normalmente e depois cria a nota
                    StartApplication();
                    Dispatcher.BeginInvoke(new Action(() =>
                    {
                        var frame = NoteWindowManager.Shared.SuggestedFrame();
                        var note = Models.NoteStore.Shared.CreateNote(folder, frame);
                        NoteWindowManager.Shared.ShowNoteWindow(note);
                    }));
                }
            }
            else
            {
                if (!createdNew)
                {
                    MessageBox.Show("O The Styk já está rodando em segundo plano perto do relógio.");
                    Shutdown();
                    return;
                }

                StartApplication();
            }
        }

        private void StartApplication()
        {
            // Evita que a aplicação WPF se encerre automaticamente quando não houver janelas abertas
            ShutdownMode = ShutdownMode.OnExplicitShutdown;

            // Registra as chaves de menu de contexto no registro do Windows (HKCU)
            ShellIntegration.RegisterContextMenu();

            // Inicia o servidor IPC em segundo plano para escutar cliques do menu de contexto
            StartIPCServer();

            // Inicializa o Observer do Windows Explorer
            _observer = new ExplorerObserver();
            _observer.Change += Observer_Change;

            // Inicializa o ícone de bandeja (System Tray) e menu
            _trayController = new TrayController(_observer);

            // Inicia o loop de monitoramento
            _observer.Start();
        }

        private void StartIPCServer()
        {
            var thread = new Thread(() =>
            {
                while (true)
                {
                    try
                    {
                        using (var pipeServer = new NamedPipeServerStream(PipeName, PipeDirection.In))
                        {
                            pipeServer.WaitForConnection();
                            using (var reader = new StreamReader(pipeServer))
                            {
                                string? folder = reader.ReadLine();
                                if (!string.IsNullOrEmpty(folder))
                                {
                                    // Executa na thread principal da UI para criar e focar a nota
                                    Dispatcher.BeginInvoke(new Action(() =>
                                    {
                                        var frame = NoteWindowManager.Shared.SuggestedFrame();
                                        var note = Models.NoteStore.Shared.CreateNote(folder, frame);
                                        NoteWindowManager.Shared.ShowNoteWindow(note);
                                    }));
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"Erro no servidor IPC: {ex.Message}");
                        Thread.Sleep(1000);
                    }
                }
            })
            {
                IsBackground = true
            };
            thread.Start();
        }

        private static void SendIPCCommand(string folderPath)
        {
            try
            {
                using (var pipeClient = new NamedPipeClientStream(".", PipeName, PipeDirection.Out))
                {
                    pipeClient.Connect(1000); // 1s timeout
                    using (var writer = new StreamWriter(pipeClient))
                    {
                        writer.WriteLine(folderPath);
                        writer.Flush();
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Erro ao enviar comando IPC: {ex.Message}");
            }
        }

        private void Observer_Change(string? folderPath, RECT? windowBounds)
        {
            // Atualiza o WindowManager para abrir/fechar/mover as notas correspondentes
            NoteWindowManager.Shared.SetVisibleFolder(folderPath, windowBounds);
        }

        private void Application_Exit(object sender, ExitEventArgs e)
        {
            // Garante que todas as alterações pendentes sejam salvas no disco
            NoteWindowManager.Shared.FlushAll();

            // Libera os recursos de tray icon e loops
            _observer?.Stop();
            _trayController?.Dispose();
            _mutex?.ReleaseMutex();
        }
    }
}
