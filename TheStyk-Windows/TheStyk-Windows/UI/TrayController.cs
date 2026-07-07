using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using Forms = System.Windows.Forms;
using TheStyk.Models;
using TheStyk.SystemIntegration;
using MessageBox = System.Windows.MessageBox;
using Application = System.Windows.Application;

namespace TheStyk.UI
{
    public class TrayController : IDisposable
    {
        private readonly Forms.NotifyIcon _notifyIcon;
        private readonly ExplorerObserver _observer;
        private bool _disposed = false;

        public TrayController(ExplorerObserver observer)
        {
            _observer = observer;

            _notifyIcon = new Forms.NotifyIcon
            {
                Icon = CreateTrayIcon(),
                Text = "The Styk",
                Visible = true
            };

            // Associa o menu de contexto
            _notifyIcon.ContextMenuStrip = new Forms.ContextMenuStrip();
            _notifyIcon.ContextMenuStrip.Opening += ContextMenuStrip_Opening;

            // Escuta mudanças de índice no NoteStore para forçar reconstrução se o menu estiver aberto
            NoteStore.Shared.IndexChanged += NoteStore_IndexChanged;
        }

        private void NoteStore_IndexChanged(object? sender, EventArgs e)
        {
            // Se o menu estiver aberto, atualiza
            if (_notifyIcon.ContextMenuStrip != null && _notifyIcon.ContextMenuStrip.Visible)
            {
                BuildMenu();
            }
        }

        private void ContextMenuStrip_Opening(object? sender, System.ComponentModel.CancelEventArgs e)
        {
            BuildMenu();
        }

        private void BuildMenu()
        {
            var menu = _notifyIcon.ContextMenuStrip;
            if (menu == null) return;

            menu.Items.Clear();

            // 1. "Nova nota nesta pasta"
            string? currentFolder = _observer.CurrentFolder;
            if (!string.IsNullOrEmpty(currentFolder))
            {
                string shortenedFolder = AbbreviatePath(currentFolder);
                var newNoteItem = new Forms.ToolStripMenuItem($"Nova nota em \"{shortenedFolder}\"", null, (s, e) =>
                {
                    var suggestedFrame = NoteWindowManager.Shared.SuggestedFrame();
                    var note = NoteStore.Shared.CreateNote(currentFolder, suggestedFrame);
                    NoteWindowManager.Shared.ShowNoteWindow(note);
                });
                menu.Items.Add(newNoteItem);
            }
            else
            {
                var newNoteDisabled = new Forms.ToolStripMenuItem("Abra uma pasta no Explorer para criar uma nota")
                {
                    Enabled = false
                };
                menu.Items.Add(newNoteDisabled);
            }

            menu.Items.Add(new Forms.ToolStripSeparator());

            // 2. Título do Cabeçalho
            int totalNotes = NoteStore.Shared.Index.Count(n => n.Orphaned != true);
            var headerItem = new Forms.ToolStripMenuItem($"Notas ({totalNotes})")
            {
                Enabled = false
            };
            menu.Items.Add(headerItem);

            // 3. Notas por pastas (Ordenadas)
            var folders = NoteStore.Shared.Folders();
            foreach (var folder in folders)
            {
                string shortenedName = AbbreviatePath(folder);
                var folderSubmenu = new Forms.ToolStripMenuItem(shortenedName);
                
                // Item de Ação do Submenu da Pasta: "Abrir pasta no Explorer"
                bool exists = Directory.Exists(folder);
                var openFolderItem = new Forms.ToolStripMenuItem(exists ? "Abrir pasta no Explorer" : "Pasta não encontrada")
                {
                    Enabled = exists
                };
                if (exists)
                {
                    openFolderItem.Click += (s, e) => OpenInExplorer(folder);
                }
                folderSubmenu.DropDownItems.Add(openFolderItem);
                folderSubmenu.DropDownItems.Add(new Forms.ToolStripSeparator());

                // Adiciona as notas desta pasta
                var notesInFolder = NoteStore.Shared.Entries(folder);
                foreach (var noteEntry in notesInFolder)
                {
                    var noteItem = new Forms.ToolStripMenuItem(noteEntry.Snippet);
                    
                    // Bolinha de cor customizada como ícone do menu
                    noteItem.Image = CreateColorDot(noteEntry.Color);

                    // Ações da nota específica
                    var focusItem = new Forms.ToolStripMenuItem("Focar Nota", null, (s, e) =>
                    {
                        var note = NoteStore.Shared.LoadNote(noteEntry.Id);
                        if (note != null)
                        {
                            // Abre a pasta no explorer e exibe a nota
                            OpenInExplorer(folder);
                            NoteWindowManager.Shared.ShowNoteWindow(note);
                        }
                    });

                    var exportItem = new Forms.ToolStripMenuItem("Exportar...", null, (s, e) =>
                    {
                        var note = NoteStore.Shared.LoadNote(noteEntry.Id);
                        if (note != null) ExportNote(note);
                    });

                    var deleteItem = new Forms.ToolStripMenuItem("Apagar...", null, (s, e) =>
                    {
                        var result = Forms.MessageBox.Show("Apagar esta nota?", "Confirmar", Forms.MessageBoxButtons.YesNo, Forms.MessageBoxIcon.Warning);
                        if (result == Forms.DialogResult.Yes)
                        {
                            NoteWindowManager.Shared.CloseNoteWindow(noteEntry.Id);
                            NoteStore.Shared.MoveToTrash(noteEntry.Id);
                        }
                    });

                    noteItem.DropDownItems.Add(focusItem);
                    noteItem.DropDownItems.Add(exportItem);
                    noteItem.DropDownItems.Add(deleteItem);

                    folderSubmenu.DropDownItems.Add(noteItem);
                }

                menu.Items.Add(folderSubmenu);
            }

            menu.Items.Add(new Forms.ToolStripSeparator());

            // 4. Seção "Notas órfãs" (Pastas excluídas/renomeadas)
            var orphans = NoteStore.Shared.Orphans();
            if (orphans.Count > 0)
            {
                var orphansSubmenu = new Forms.ToolStripMenuItem($"Notas órfãs ({orphans.Count})")
                {
                    ForeColor = Color.DarkGoldenrod
                };

                foreach (var orphan in orphans)
                {
                    var orphanItem = new Forms.ToolStripMenuItem(orphan.Snippet);
                    orphanItem.Image = CreateColorDot(orphan.Color);

                    var reattachItem = new Forms.ToolStripMenuItem("Re-ancorar a uma pasta...", null, (s, e) =>
                    {
                        using (var fbd = new Forms.FolderBrowserDialog { Description = "Selecione a nova pasta para esta nota" })
                        {
                            if (fbd.ShowDialog() == Forms.DialogResult.OK)
                            {
                                NoteStore.Shared.Reattach(orphan.Id, fbd.SelectedPath);
                            }
                        }
                    });

                    var exportItem = new Forms.ToolStripMenuItem("Exportar...", null, (s, e) =>
                    {
                        var note = NoteStore.Shared.LoadNote(orphan.Id);
                        if (note != null) ExportNote(note);
                    });

                    var deleteItem = new Forms.ToolStripMenuItem("Apagar...", null, (s, e) =>
                    {
                        var result = Forms.MessageBox.Show("Apagar esta nota?", "Confirmar", Forms.MessageBoxButtons.YesNo, Forms.MessageBoxIcon.Warning);
                        if (result == Forms.DialogResult.Yes)
                        {
                            NoteStore.Shared.MoveToTrash(orphan.Id);
                        }
                    });

                    orphanItem.DropDownItems.Add(reattachItem);
                    orphanItem.DropDownItems.Add(exportItem);
                    orphanItem.DropDownItems.Add(deleteItem);

                    orphansSubmenu.DropDownItems.Add(orphanItem);
                }

                menu.Items.Add(orphansSubmenu);
                menu.Items.Add(new Forms.ToolStripSeparator());
            }

            // 5. Seção "Lixeira"
            var trash = NoteStore.Shared.Trash;
            if (trash.Count > 0)
            {
                var trashSubmenu = new Forms.ToolStripMenuItem($"Lixeira ({trash.Count})");
                
                foreach (var trashed in trash)
                {
                    var trashItem = new Forms.ToolStripMenuItem(trashed.Snippet);
                    trashItem.Image = CreateColorDot(trashed.Color);

                    var restoreItem = new Forms.ToolStripMenuItem("Restaurar", null, (s, e) =>
                    {
                        NoteStore.Shared.RestoreFromTrash(trashed.Id);
                    });

                    var deletePermItem = new Forms.ToolStripMenuItem("Excluir Permanentemente", null, (s, e) =>
                    {
                        var result = Forms.MessageBox.Show("Excluir permanentemente?", "Aviso", Forms.MessageBoxButtons.YesNo, Forms.MessageBoxIcon.Stop);
                        if (result == Forms.DialogResult.Yes)
                        {
                            NoteStore.Shared.DeletePermanently(trashed.Id);
                        }
                    });

                    trashItem.DropDownItems.Add(restoreItem);
                    trashItem.DropDownItems.Add(deletePermItem);

                    trashSubmenu.DropDownItems.Add(trashItem);
                }

                trashSubmenu.DropDownItems.Add(new Forms.ToolStripSeparator());
                
                var emptyTrashItem = new Forms.ToolStripMenuItem("Esvaziar Lixeira", null, (s, e) =>
                {
                    var result = Forms.MessageBox.Show("Esvaziar toda a lixeira?", "Aviso", Forms.MessageBoxButtons.YesNo, Forms.MessageBoxIcon.Stop);
                    if (result == Forms.DialogResult.Yes)
                    {
                        NoteStore.Shared.EmptyTrash();
                    }
                });
                trashSubmenu.DropDownItems.Add(emptyTrashItem);

                menu.Items.Add(trashSubmenu);
                menu.Items.Add(new Forms.ToolStripSeparator());
            }

            // 6. Sobre e Sair
            var aboutItem = new Forms.ToolStripMenuItem("Sobre o The Styk", null, (s, e) =>
            {
                var aboutWin = new AboutWindow();
                aboutWin.Show();
            });
            menu.Items.Add(aboutItem);

            var exitItem = new Forms.ToolStripMenuItem("Sair do The Styk", null, (s, e) =>
            {
                Application.Current.Shutdown();
            });
            menu.Items.Add(exitItem);
        }

        private static string AbbreviatePath(string path)
        {
            if (string.IsNullOrEmpty(path)) return string.Empty;

            // Tenta abreviar o caminho do usuário
            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            if (path.StartsWith(userProfile, StringComparison.OrdinalIgnoreCase))
            {
                return "~" + path.Substring(userProfile.Length).Replace("\\", "/");
            }

            // Retorna o nome da pasta final se for muito grande
            if (path.Length > 35)
            {
                string folderName = Path.GetFileName(path);
                if (string.IsNullOrEmpty(folderName) && path.Contains("/"))
                {
                    folderName = path.Split('/').LastOrDefault();
                }
                return string.IsNullOrEmpty(folderName) ? path : ".../" + folderName;
            }

            return path.Replace("\\", "/");
        }

        private static void OpenInExplorer(string folderPath)
        {
            try
            {
                string winPath = folderPath.Replace("/", "\\");
                if (Directory.Exists(winPath))
                {
                    Process.Start("explorer.exe", $"\"{winPath}\"");
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Erro ao abrir pasta: {ex.Message}");
            }
        }

        private static void ExportNote(Note note)
        {
            // Código compartilhado com o NoteWindow para exportar arquivos
            string snippet = NoteStore.MakeSnippet(note.Text);
            string sanitizedSnippet = Regex.Replace(snippet, @"[\\/:*?""<>|]", "");
            if (sanitizedSnippet.Length > 50) sanitizedSnippet = sanitizedSnippet.Substring(0, 50);
            if (string.IsNullOrWhiteSpace(sanitizedSnippet) || sanitizedSnippet == "Nota vazia") sanitizedSnippet = "Nota";

            var sfd = new Microsoft.Win32.SaveFileDialog
            {
                Filter = "Arquivos de Texto (*.txt)|*.txt|Todos os Arquivos (*.*)|*.*",
                FileName = $"The Styk – {sanitizedSnippet}.txt",
                Title = "Exportar Nota"
            };

            if (sfd.ShowDialog() == true)
            {
                try
                {
                    File.WriteAllText(sfd.FileName, note.Text, System.Text.Encoding.UTF8);
                }
                catch (Exception ex)
                {
                    MessageBox.Show($"Erro ao exportar nota: {ex.Message}", "Erro", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }

        private static Bitmap CreateColorDot(NoteColor noteColor)
        {
            var brushColor = Theme.GetColor(noteColor);
            var bmp = new Bitmap(10, 10);
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);
                using (var brush = new SolidBrush(Color.FromArgb(brushColor.R, brushColor.G, brushColor.B)))
                {
                    g.FillEllipse(brush, 0, 0, 9, 9);
                }
                using (var pen = new Pen(Color.FromArgb(60, 0, 0, 0), 1))
                {
                    g.DrawEllipse(pen, 0, 0, 9, 9);
                }
            }
            return bmp;
        }

        private static Icon CreateTrayIcon()
        {
            // Cria um Bitmap 16x16 programaticamente com um ícone de post-it amarelo dobrado
            var bmp = new Bitmap(16, 16);
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);

                // Preenchimento amarelo
                using (var brush = new SolidBrush(Color.FromArgb(255, 224, 102)))
                {
                    g.FillRectangle(brush, 2, 2, 12, 12);
                }

                // Borda preta translúcida
                using (var pen = new Pen(Color.FromArgb(120, 0, 0, 0), 1))
                {
                    g.DrawRectangle(pen, 2, 2, 12, 12);
                }

                // Linhas simulando texto
                using (var linePen = new Pen(Color.FromArgb(180, 28, 28, 30), 1))
                {
                    g.DrawLine(linePen, 4, 5, 11, 5);
                    g.DrawLine(linePen, 4, 8, 9, 8);
                }
            }
            return Icon.FromHandle(bmp.GetHicon());
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                NoteStore.Shared.IndexChanged -= NoteStore_IndexChanged;
                _notifyIcon.Dispose();
                _disposed = true;
                GC.SuppressFinalize(this);
            }
        }
    }
}
