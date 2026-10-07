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


            if (string.IsNullOrEmpty(folder) || !bounds.HasValue)
            {
                // Nenhuma pasta ativa no Explorer: fecha todos os painéis visíveis
                var openIds = _openWindows.Keys.ToList();
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
            foreach (var entry in entriesInFolder)
            {
                if (!_openWindows.ContainsKey(entry.Id))
                {
                    var note = NoteStore.Shared.LoadNote(entry.Id);
                    if (note != null)
                    {
                        CreateAndShowNoteWindow(note);
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
            var win = new UI.NoteWindow(note);
            win.Closed += (s, e) =>
            {
                _openWindows.Remove(note.Id);
            };

            _openWindows[note.Id] = win;
            
            win.Show();
        }
    }
}
