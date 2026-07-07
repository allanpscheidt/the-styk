using System;
using System.Diagnostics;
using Microsoft.Win32;

namespace TheStyk.SystemIntegration
{
    public static class ShellIntegration
    {
        public static void RegisterContextMenu()
        {
            try
            {
                // Obtém o caminho do executável atual em execução
                string? exePath = Environment.ProcessPath;
                if (string.IsNullOrEmpty(exePath)) return;

                // 1. Registro para clique com botão direito EM CIMA de uma pasta (Directory)
                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Classes\directory\shell\TheStyk"))
                {
                    key.SetValue("", "Criar nota do The Styk");
                    // Adiciona um ícone ao menu de contexto (usa o próprio ícone do executável)
                    key.SetValue("Icon", exePath);

                    using (RegistryKey cmdKey = key.CreateSubKey("command"))
                    {
                        cmdKey.SetValue("", $"\"{exePath}\" \"-create\" \"%1\"");
                    }
                }

                // 2. Registro para clique com botão direito NO FUNDO/ESPAÇO VAZIO de uma pasta (Directory Background)
                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Classes\directory\Background\shell\TheStyk"))
                {
                    key.SetValue("", "Criar nota do The Styk");
                    key.SetValue("Icon", exePath);

                    using (RegistryKey cmdKey = key.CreateSubKey("command"))
                    {
                        cmdKey.SetValue("", $"\"{exePath}\" \"-create\" \"%V\"");
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Erro ao registrar menu de contexto no Windows: {ex.Message}");
            }
        }
    }
}
