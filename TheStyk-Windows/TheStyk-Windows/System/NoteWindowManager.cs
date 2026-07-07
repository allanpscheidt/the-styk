using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using TheStyk.Models;

namespace TheStyk.SystemIntegration
{
    public class NoteWindowManager
    {
        private static readonly Lazy<NoteWindowManager> _instance = new(() => new NoteWindowManager());
        public static NoteWindowManager Shared => _instance.Value;

        private readonly Dictionary<Guid, UI.NoteWindow> _openWindows = new();
        private string? _currentFolder;
        private RECT? _currentBounds;

        public RECT? CurrentExplorerBounds => _currentBounds;
        public string? CurrentFolder => _currentFolder;

        private NoteWindowManager() { }

        public void SetVisibleFolder(string? folder, RECT? bounds)
        {
            _currentFolder = folder;
            _currentBounds = bounds;

            ExplorerObserver.Log($"[WindowManager] SetVisibleFolder: folder='{folder ?? "null"}', hasBounds={bounds.HasValue}");

            if (string.IsNullOrEmpty(folder) || !bounds.HasValue)
            {
                // Nenhuma pasta ativa no Explorer: fecha todos os painéis visíveis
                var openIds = _openWindows.Keys.ToList();
                if (openIds.Count > 0)
                {
                    ExplorerObserver.Log($"[WindowManager] Nenhuma pasta ativa. Fechando {openIds.Count} notas abertas.");
                }
                foreach (var id in openIds)
                {
                    if (_openWindows.TryGetValue(id, out var win))
                    {
                        win.FlushPendingSave();
                        win.Close();
                    }
                }
                _openWindows.Clear();
                return;
            }

            // RECONCILIAÇÃO:
            // 1. Fecha notas de outras pastas que estejam abertas
            var toClose = _openWindows.Where(kvp =>
            {
                var note = NoteStore.Shared.LoadNote(kvp.Key);
                return note == null || !string.Equals(note.Folder, folder, StringComparison.OrdinalIgnoreCase);
            }).Select(kvp => kvp.Key).ToList();

            if (toClose.Count > 0)
            {
                ExplorerObserver.Log($"[WindowManager] Fechando {toClose.Count} notas de outras pastas.");
            }
            foreach (var id in toClose)
            {
                if (_openWindows.TryGetValue(id, out var win))
                {
                    win.FlushPendingSave();
                    win.Close();
                    _openWindows.Remove(id);
                }
            }

            // 2. Cria e abre notas da pasta ativa que ainda não estejam abertas
            var entriesInFolder = NoteStore.Shared.Entries(folder);
            ExplorerObserver.Log($"[WindowManager] Encontrou {entriesInFolder.Count} notas no index para '{folder}'");
            foreach (var entry in entriesInFolder)
            {
                if (!_openWindows.ContainsKey(entry.Id))
                {
                    ExplorerObserver.Log($"[WindowManager] Carregando nota {entry.Id} para '{folder}'...");
                    var note = NoteStore.Shared.LoadNote(entry.Id);
                    if (note != null)
                    {
                        ExplorerObserver.Log($"[WindowManager] Nota {entry.Id} carregada do disco. Criando janela...");
                        CreateAndShowNoteWindow(note);
                    }
                    else
                    {
                        ExplorerObserver.Log($"[WindowManager] Falha ao carregar nota {entry.Id} do disco!");
                    }
                }
            }

            // 3. Atualiza as posições de todas as notas abertas para acompanhar a janela do Explorer
            foreach (var win in _openWindows.Values)
            {
                win.UpdatePositionFromExplorer(bounds.Value);
            }
        }

        public NoteFrame SuggestedFrame()
        {
            double screenWidth = SystemParameters.PrimaryScreenWidth;
            double screenHeight = SystemParameters.PrimaryScreenHeight;

            // Padrão: 260x240 perto do centro da tela primária
            double x = (screenWidth - 260) / 2;
            double y = (screenHeight - 240) / 2;

            // Se houver uma janela ativa do Explorer, tenta centralizar nela
            if (_currentBounds.HasValue)
            {
                var eb = _currentBounds.Value;
                x = eb.Left + (eb.Width - 260) / 2;
                y = eb.Top + (eb.Height - 240) / 2;
            }

            // Efeito cascata: adiciona +24px para cada nota aberta
            int count = _openWindows.Count;
            x += count * 24;
            y += count * 24;

            return new NoteFrame { X = x, Y = y, W = 260, H = 240 };
        }

        public void ShowNoteWindow(Note note)
        {
            if (_openWindows.ContainsKey(note.Id))
            {
                _openWindows[note.Id].Activate();
                return;
            }

            CreateAndShowNoteWindow(note);
            
            // Se o Explorer estiver ativo, atualiza a posição imediatamente
            if (_currentBounds.HasValue)
            {
                _openWindows[note.Id].UpdatePositionFromExplorer(_currentBounds.Value);
            }
        }

        public void CloseNoteWindow(Guid noteId)
        {
            if (_openWindows.TryGetValue(noteId, out var win))
            {
                win.FlushPendingSave();
                win.Close();
                _openWindows.Remove(noteId);
            }
        }

        public void FlushAll()
        {
            foreach (var win in _openWindows.Values)
            {
                win.FlushPendingSave();
            }
        }

        private void CreateAndShowNoteWindow(Note note)
        {
            ExplorerObserver.Log($"[WindowManager] Instanciando NoteWindow para nota {note.Id}...");
            var win = new UI.NoteWindow(note);
            win.Closed += (s, e) =>
            {
                ExplorerObserver.Log($"[WindowManager] NoteWindow fechada para nota {note.Id}");
                _openWindows.Remove(note.Id);
            };

            _openWindows[note.Id] = win;
            
            ExplorerObserver.Log($"[WindowManager] Chamando win.Show() para nota {note.Id}...");
            win.Show();
            ExplorerObserver.Log($"[WindowManager] win.Show() concluida para nota {note.Id}");
        }
    }
}
