using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using TheStyk.Models;

namespace TheStyk.Models
{
    public class NoteStore
    {
        private static readonly Lazy<NoteStore> _instance = new(() => new NoteStore());
        public static NoteStore Shared => _instance.Value;

        public static readonly string IndexDidChangeNotification = "thestyk.indexDidChange";
        public event EventHandler? IndexChanged;

        private const long MaxNoteBytes = 2 * 1024 * 1024; // 2 MB
        private const long MaxIndexBytes = 5 * 1024 * 1024; // 5 MB
        private const int MaxEntries = 10000;
        private const int MaxTextChars = 200000;
        private static readonly TimeSpan TrashRetention = TimeSpan.FromDays(5);

        private readonly string _dataDir;
        private readonly string _notesDir;
        private readonly string _trashDir;
        private readonly string _indexFile;

        private readonly List<IndexEntry> _index = new();
        private readonly List<TrashEntry> _trash = new();
        private DateTime _lastReconcile = DateTime.MinValue;

        private readonly JsonSerializerOptions _jsonOptions;

        public IReadOnlyList<IndexEntry> Index => _index.AsReadOnly();
        public IReadOnlyList<TrashEntry> Trash => _trash.AsReadOnly();

        private NoteStore()
        {
            // Busca diretório personalizado por Env (útil para testes isolados)
            string? envDir = Environment.GetEnvironmentVariable("THESTYK_DATA_DIR");
            if (!string.IsNullOrEmpty(envDir))
            {
                _dataDir = envDir;
            }
            else
            {
                _dataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "The Styk");
            }

            _notesDir = Path.Combine(_dataDir, "notes");
            _trashDir = Path.Combine(_dataDir, "trash");
            _indexFile = Path.Combine(_dataDir, "index.json");

            Directory.CreateDirectory(_dataDir);
            Directory.CreateDirectory(_notesDir);
            Directory.CreateDirectory(_trashDir);

            _jsonOptions = new JsonSerializerOptions
            {
                WriteIndented = true,
                DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
            };

            ReloadFromDisk();
            PurgeExpiredTrash();
        }

        public void ReloadFromDisk()
        {
            _index.Clear();
            _trash.Clear();

            var loaded = LoadIndexFile(_indexFile);
            _index.AddRange(loaded.Index);
            _trash.AddRange(loaded.Trash);

            PostIndexDidChange();
        }

        public static string NormalizePath(string path)
        {
            if (string.IsNullOrEmpty(path)) return string.Empty;
            
            // Substitui contra-barras por barras estilo POSIX para compatibilidade no index
            string normalized = path.Replace("\\", "/");

            // No Windows, caminhos de rede podem começar com "//" (UNC).
            // Remove barra final de caminhos normais (ex: "C:/Users/" vira "C:/Users", mas "C:/" permanece "C:/")
            if (normalized.EndsWith("/") && normalized.Length > 3)
            {
                normalized = normalized.TrimEnd('/');
            }

            return normalized;
        }

        // MARK: - Consulta

        public List<IndexEntry> Entries(string folder)
        {
            string normalized = NormalizePath(folder);
            // Comparação case-insensitive para caminhos do Windows
            return _index.Where(e => string.Equals(e.Folder, normalized, StringComparison.OrdinalIgnoreCase)).ToList();
        }

        public List<string> Folders()
        {
            return _index
                .Where(e => e.Orphaned != true)
                .Select(e => e.Folder)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(f => f)
                .ToList();
        }

        public List<IndexEntry> Orphans()
        {
            return _index.Where(e => e.Orphaned == true).ToList();
        }

        // MARK: - Lazy load da nota completa

        public Note? LoadNote(Guid id)
        {
            string path = GetNotePath(id);
            if (!File.Exists(path))
            {
                SystemIntegration.ExplorerObserver.Log($"[NoteStore] LoadNote falhou: Arquivo nao existe em '{path}'");
                return null;
            }

            try
            {
                var fileInfo = new FileInfo(path);
                if (fileInfo.Length > MaxNoteBytes)
                {
                    SystemIntegration.ExplorerObserver.Log($"[NoteStore] LoadNote falhou: Tamanho do arquivo {fileInfo.Length} excede o limite {MaxNoteBytes}");
                    return null;
                }

                byte[] data = File.ReadAllBytes(path);
                if (data.Length > MaxNoteBytes)
                {
                    SystemIntegration.ExplorerObserver.Log($"[NoteStore] LoadNote falhou: Tamanho dos bytes {data.Length} excede o limite {MaxNoteBytes}");
                    return null;
                }

                // Pula o UTF-8 BOM se presente (0xEF, 0xBB, 0xBF) para evitar erro no JsonSerializer
                ReadOnlySpan<byte> span = data;
                if (span.Length >= 3 && span[0] == 0xEF && span[1] == 0xBB && span[2] == 0xBF)
                {
                    span = span.Slice(3);
                }

                var note = JsonSerializer.Deserialize<Note>(span, _jsonOptions);
                if (note == null)
                {
                    SystemIntegration.ExplorerObserver.Log($"[NoteStore] LoadNote falhou: Deserializacao JSON retornou null");
                    return null;
                }
                if (note.Id != id)
                {
                    SystemIntegration.ExplorerObserver.Log($"[NoteStore] LoadNote falhou: ID da nota ({note.Id}) nao bate com o ID buscado ({id})");
                    return null;
                }

                // Validações de guardrail
                if (string.IsNullOrEmpty(note.Folder))
                {
                    SystemIntegration.ExplorerObserver.Log($"[NoteStore] LoadNote falhou: Folder da nota esta vazio ou nulo");
                    return null;
                }

                note.Folder = NormalizePath(note.Folder);
                if (note.Text.Length > MaxTextChars)
                {
                    note.Text = note.Text.Substring(0, MaxTextChars);
                }

                note.Style = new NoteStyle
                {
                    Color = note.Style.Color,
                    FontID = note.Style.FontID,
                    FontSize = Clamp(note.Style.FontSize, 8, 72)
                };

                note.Frame = new NoteFrame
                {
                    X = double.IsFinite(note.Frame.X) ? note.Frame.X : 0,
                    Y = double.IsFinite(note.Frame.Y) ? note.Frame.Y : 0,
                    W = Clamp(note.Frame.W, 120, 4000),
                    H = Clamp(note.Frame.H, 120, 4000)
                };

                return note;
            }
            catch (Exception ex)
            {
                SystemIntegration.ExplorerObserver.Log($"[NoteStore] Erro ao carregar nota {id}: {ex.Message}\n{ex.StackTrace}");
                return null;
            }
        }

        // MARK: - Mutação

        public Note CreateNote(string folder, NoteFrame frame)
        {
            var now = DateTime.UtcNow;
            var note = new Note
            {
                Id = Guid.NewGuid(),
                Folder = NormalizePath(folder),
                Text = string.Empty,
                Style = new NoteStyle { Color = NoteColor.yellow, FontID = NoteFontID.system, FontSize = 14 },
                Frame = frame,
                Created = now,
                Modified = now
            };

            WriteNoteFile(note);

            _index.Add(CreateIndexEntry(note));
            WriteIndex();
            PostIndexDidChange();

            return note;
        }

        public void Save(Note note)
        {
            note.Modified = DateTime.UtcNow;
            note.Folder = NormalizePath(note.Folder);

            if (note.Text.Length > MaxTextChars)
            {
                note.Text = note.Text.Substring(0, MaxTextChars);
            }

            WriteNoteFile(note);

            var entry = CreateIndexEntry(note);
            int idx = _index.FindIndex(e => e.Id == note.Id);
            if (idx >= 0)
            {
                _index[idx] = entry;
            }
            else
            {
                _index.Add(entry);
            }

            WriteIndex();
            PostIndexDidChange();
        }

        // MARK: - Lixeira (recuperável por 5 dias)

        public void MoveToTrash(Guid id)
        {
            int idx = _index.FindIndex(e => e.Id == id);
            if (idx < 0) return;

            var entry = _index[idx];
            _index.RemoveAt(idx);

            string sourcePath = GetNotePath(id);
            string destPath = Path.Combine(_trashDir, id + ".json");

            try
            {
                if (File.Exists(destPath)) File.Delete(destPath);
                if (File.Exists(sourcePath))
                {
                    File.Move(sourcePath, destPath);
                    _trash.Add(new TrashEntry
                    {
                        Id = entry.Id,
                        Folder = entry.Folder,
                        Snippet = entry.Snippet,
                        Color = entry.Color,
                        DeletedAt = DateTime.UtcNow
                    });
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"The Styk: falha ao mover nota {id} para lixeira: {ex.Message}");
                if (File.Exists(sourcePath)) File.Delete(sourcePath);
            }

            WriteIndex();
            PostIndexDidChange();
        }

        public void RestoreFromTrash(Guid id)
        {
            int idx = _trash.FindIndex(t => t.Id == id);
            if (idx < 0) return;

            var trashEntry = _trash[idx];
            string sourcePath = Path.Combine(_trashDir, id + ".json");
            string destPath = GetNotePath(id);

            try
            {
                if (File.Exists(sourcePath))
                {
                    if (File.Exists(destPath)) File.Delete(destPath);
                    File.Move(sourcePath, destPath);
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"The Styk: falha ao restaurar nota {id}: {ex.Message}");
                return;
            }

            _trash.RemoveAt(idx);

            // Verifica se a pasta original existe. Se não existir, vira órfã.
            bool folderExists = Directory.Exists(trashEntry.Folder);

            _index.Add(new IndexEntry
            {
                Id = trashEntry.Id,
                Folder = trashEntry.Folder,
                Snippet = trashEntry.Snippet,
                Color = trashEntry.Color,
                Modified = DateTime.UtcNow,
                Orphaned = folderExists ? null : true
            });

            WriteIndex();
            PostIndexDidChange();
        }

        public void DeletePermanently(Guid id)
        {
            _trash.RemoveAll(t => t.Id == id);
            string trashPath = Path.Combine(_trashDir, id + ".json");
            try
            {
                if (File.Exists(trashPath)) File.Delete(trashPath);
            }
            catch {}

            WriteIndex();
            PostIndexDidChange();
        }

        public void EmptyTrash()
        {
            foreach (var t in _trash)
            {
                string path = Path.Combine(_trashDir, t.Id + ".json");
                try { if (File.Exists(path)) File.Delete(path); } catch {}
            }
            _trash.Clear();
            WriteIndex();
            PostIndexDidChange();
        }

        private void PurgeExpiredTrash()
        {
            DateTime cutoff = DateTime.UtcNow - TrashRetention;
            var expired = _trash.Where(t => t.DeletedAt < cutoff).ToList();
            if (expired.Count == 0) return;

            foreach (var t in expired)
            {
                string path = Path.Combine(_trashDir, t.Id + ".json");
                try { if (File.Exists(path)) File.Delete(path); } catch {}
            }

            _trash.RemoveAll(t => t.DeletedAt < cutoff);
            WriteIndex();
            PostIndexDidChange();
        }

        // MARK: - Âncoras: pasta apagada vira órfã, recriada des-órfã

        public void Reattach(Guid id, string toFolder)
        {
            var note = LoadNote(id);
            if (note == null) return;

            string normalizedFolder = NormalizePath(toFolder);
            note.Folder = normalizedFolder;
            note.Modified = DateTime.UtcNow;

            WriteNoteFile(note);

            int idx = _index.FindIndex(e => e.Id == id);
            if (idx >= 0)
            {
                _index[idx].Folder = normalizedFolder;
                _index[idx].Orphaned = null;
                _index[idx].Modified = note.Modified;
            }

            WriteIndex();
            PostIndexDidChange();
        }

        public void ReconcileAnchorsIfStale()
        {
            if ((DateTime.UtcNow - _lastReconcile).TotalSeconds > 30)
            {
                ReconcileAnchors();
            }
        }

        public void ReconcileAnchors()
        {
            _lastReconcile = DateTime.UtcNow;
            bool changed = false;

            // Agrupa por pasta única
            var folders = _index.Select(e => e.Folder).Distinct().ToList();

            foreach (var folder in folders)
            {
                bool exists = Directory.Exists(folder);
                bool isOrphan = _index.Any(e => string.Equals(e.Folder, folder, StringComparison.OrdinalIgnoreCase) && e.Orphaned == true);

                if (exists)
                {
                    if (isOrphan)
                    {
                        // Pasta voltou a existir -> deixa de ser órfã
                        foreach (var entry in _index.Where(e => string.Equals(e.Folder, folder, StringComparison.OrdinalIgnoreCase)))
                        {
                            entry.Orphaned = null;
                        }
                        changed = true;
                    }
                }
                else
                {
                    if (!isOrphan)
                    {
                        // Pasta sumiu -> vira órfã
                        foreach (var entry in _index.Where(e => string.Equals(e.Folder, folder, StringComparison.OrdinalIgnoreCase)))
                        {
                            entry.Orphaned = true;
                        }
                        changed = true;
                    }
                }
            }

            if (changed)
            {
                WriteIndex();
                PostIndexDidChange();
            }
        }

        // MARK: - Disco

        private string GetNotePath(Guid id) => Path.Combine(_notesDir, id + ".json");

        private void WriteNoteFile(Note note)
        {
            try
            {
                string path = GetNotePath(note.Id);
                string json = JsonSerializer.Serialize(note, _jsonOptions);
                WriteFileAtomic(path, json);
            }
            catch (Exception ex)
            {
                SystemIntegration.ExplorerObserver.Log($"[NoteStore] Falha ao gravar nota {note.Id}: {ex.Message}\n{ex.StackTrace}");
            }
        }

        private void WriteIndex()
        {
            try
            {
                var root = new
                {
                    version = 1,
                    notes = _index,
                    trash = _trash
                };
                string json = JsonSerializer.Serialize(root, _jsonOptions);
                WriteFileAtomic(_indexFile, json);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"The Styk: falha ao gravar index.json: {ex.Message}");
            }
        }

        private static void WriteFileAtomic(string filePath, string content)
        {
            string tempPath = filePath + ".tmp";
            // Usa UTF-8 sem BOM (Byte Order Mark) para compatibilidade com JsonSerializer.Deserialize
            var encoding = new System.Text.UTF8Encoding(false);
            File.WriteAllText(tempPath, content, encoding);

            try
            {
                if (File.Exists(filePath))
                {
                    File.Replace(tempPath, filePath, null);
                }
                else
                {
                    File.Move(tempPath, filePath);
                }
            }
            catch
            {
                // Fallback caso File.Replace fale devido a restrições/travas temporárias
                File.Copy(tempPath, filePath, true);
                File.Delete(tempPath);
            }
        }

        private static (List<IndexEntry> Index, List<TrashEntry> Trash) LoadIndexFile(string path)
        {
            var entries = new List<IndexEntry>();
            var trashed = new List<TrashEntry>();

            if (!File.Exists(path)) return (entries, trashed);

            try
            {
                var fileInfo = new FileInfo(path);
                if (fileInfo.Length > MaxIndexBytes) return (entries, trashed);

                byte[] data = File.ReadAllBytes(path);
                if (data.Length > MaxIndexBytes) return (entries, trashed); // TOCTOU guard

                using (var doc = JsonDocument.Parse(data))
                {
                    var root = doc.RootElement;
                    
                    if (root.TryGetProperty("notes", out var notesProp) && notesProp.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var item in notesProp.EnumerateArray())
                        {
                            if (entries.Count >= MaxEntries) break;
                            try
                            {
                                var entry = JsonSerializer.Deserialize<IndexEntry>(item.GetRawText());
                                if (entry != null && !string.IsNullOrEmpty(entry.Folder))
                                {
                                    entry.Folder = NormalizePath(entry.Folder);
                                    entry.Snippet = MakeSnippet(entry.Snippet);
                                    entries.Add(entry);
                                }
                            }
                            catch { /* Descarta entrada malformada silenciando */ }
                        }
                    }

                    if (root.TryGetProperty("trash", out var trashProp) && trashProp.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var item in trashProp.EnumerateArray())
                        {
                            if (trashed.Count >= MaxEntries) break;
                            try
                            {
                                var entry = JsonSerializer.Deserialize<TrashEntry>(item.GetRawText());
                                if (entry != null && !string.IsNullOrEmpty(entry.Folder))
                                {
                                    entry.Folder = NormalizePath(entry.Folder);
                                    entry.Snippet = MakeSnippet(entry.Snippet);
                                    trashed.Add(entry);
                                }
                            }
                            catch { /* Descarta entrada malformada silenciando */ }
                        }
                    }
                }
            }
            catch
            {
                // Descarta, nunca crasha
            }

            return (entries, trashed);
        }

        // MARK: - Helpers

        private IndexEntry CreateIndexEntry(Note note)
        {
            return new IndexEntry
            {
                Id = note.Id,
                Folder = note.Folder,
                Snippet = MakeSnippet(note.Text),
                Color = note.Style.Color,
                Modified = note.Modified
            };
        }

        public static string MakeSnippet(string text)
        {
            if (string.IsNullOrEmpty(text)) return "Nota vazia";

            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            foreach (var line in lines)
            {
                var cleanChars = new System.Text.StringBuilder();
                foreach (char c in line)
                {
                    var cat = char.GetUnicodeCategory(c);
                    if (cat != System.Globalization.UnicodeCategory.Control &&
                        cat != System.Globalization.UnicodeCategory.Format)
                    {
                        cleanChars.Append(c);
                    }
                }
                string clean = cleanChars.ToString().Trim();
                if (!string.IsNullOrEmpty(clean))
                {
                    return clean.Length > 60 ? clean.Substring(0, 60) : clean;
                }
            }

            return "Nota vazia";
        }

        private static double Clamp(double v, double lo, double hi)
        {
            if (!double.IsFinite(v)) return lo;
            return Math.Min(Math.Max(v, lo), hi);
        }

        private void PostIndexDidChange()
        {
            // Notifica na thread principal se possível (ou dispara o event delegate)
            var context = SynchronizationContext.Current;
            if (context != null)
            {
                context.Post(_ => IndexChanged?.Invoke(this, EventArgs.Empty), null);
            }
            else
            {
                IndexChanged?.Invoke(this, EventArgs.Empty);
            }
        }
    }
}
