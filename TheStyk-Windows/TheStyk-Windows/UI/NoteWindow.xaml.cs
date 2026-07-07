using System;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using TheStyk.Models;
using TheStyk.SystemIntegration;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using Button = System.Windows.Controls.Button;
using SaveFileDialog = Microsoft.Win32.SaveFileDialog;
using MessageBox = System.Windows.MessageBox;

namespace TheStyk.UI
{
    public partial class NoteWindow : Window
    {
        private Note _note;
        private readonly Guid _noteId;
        private bool _isLoaded = false;

        // Timers para debouncing de salvamento no disco
        private readonly DispatcherTimer _saveTextTimer;
        private readonly DispatcherTimer _saveFrameTimer;

        // Âncoras relativas à janela do Windows Explorer
        private double _anchorDx = 0;
        private double _anchorDy = 0;
        private bool _isPositioningFromExplorer = false;

        public NoteWindow(Note note)
        {
            InitializeComponent();

            _note = note;
            _noteId = note.Id;

            ExplorerObserver.Log($"[NoteWindow] Construtor iniciado para nota {_noteId}");

            // Clampa a posição inicial para estar visível na tela virtual
            double screenWidth = SystemParameters.VirtualScreenWidth;
            double screenHeight = SystemParameters.VirtualScreenHeight;

            double initialLeft = _note.Frame.X;
            double initialTop = _note.Frame.Y;

            if (initialLeft < SystemParameters.VirtualScreenLeft || initialLeft > SystemParameters.VirtualScreenLeft + screenWidth - 100)
            {
                initialLeft = SystemParameters.VirtualScreenLeft + 100;
            }
            if (initialTop < SystemParameters.VirtualScreenTop || initialTop > SystemParameters.VirtualScreenTop + screenHeight - 100)
            {
                initialTop = SystemParameters.VirtualScreenTop + 100;
            }

            Left = initialLeft;
            Top = initialTop;
            Width = Math.Clamp(_note.Frame.W, MinWidth, 4000);
            Height = Math.Clamp(_note.Frame.H, MinHeight, 4000);

            ExplorerObserver.Log($"[NoteWindow] Construtor finalizado para nota {_noteId}. Left={Left}, Top={Top}, Width={Width}, Height={Height}");

            // Timer de salvamento de texto: debounce de 1.5s
            _saveTextTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(1500)
            };
            _saveTextTimer.Tick += (s, e) =>
            {
                _saveTextTimer.Stop();
                SaveText();
            };

            // Timer de salvamento de frame (posição/tamanho): debounce de 0.5s
            _saveFrameTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(500)
            };
            _saveFrameTimer.Tick += (s, e) =>
            {
                _saveFrameTimer.Stop();
                SaveFrame();
            };

            Loaded += NoteWindow_Loaded;
            LocationChanged += NoteWindow_LocationChanged;
            SizeChanged += NoteWindow_SizeChanged;
            Closing += NoteWindow_Closing;
        }

        private void NoteWindow_Loaded(object sender, RoutedEventArgs e)
        {
            ExplorerObserver.Log($"[NoteWindow] Evento Loaded disparado para nota {_noteId}");
            ApplyStyle();
            NoteTextBox.Text = _note.Text;
            _isLoaded = true;
            ExplorerObserver.Log($"[NoteWindow] Evento Loaded concluido para nota {_noteId}");
        }

        private void ApplyStyle()
        {
            // Aplica cor pastel de fundo com opacidade ~0.9 para visual limpo/translúcido
            CardBorder.Background = Theme.GetBrush(_note.Style.Color, 0.90);
            
            // Aplica fonte e tamanho
            NoteTextBox.FontFamily = Theme.GetFontFamily(_note.Style.FontID);
            NoteTextBox.FontSize = _note.Style.FontSize;
            NoteTextBox.Foreground = Theme.GetTextBrush();
            NoteTextBox.CaretBrush = Theme.GetTextBrush();
        }

        // Método chamado pelo WindowManager quando a janela do Explorer ativa é reposicionada
        public void UpdatePositionFromExplorer(RECT explorerBounds)
        {
            _isPositioningFromExplorer = true;

            ExplorerObserver.Log($"[NoteWindow] UpdatePositionFromExplorer para nota {_noteId}: Explorer={explorerBounds.Left},{explorerBounds.Top} ({explorerBounds.Width}x{explorerBounds.Height}), Left={Left}, Top={Top}");

            // Se for a primeira ancoragem ou o usuário acabou de abrir a pasta, calcula
            if (_anchorDx == 0 && _anchorDy == 0)
            {
                RecalculateAnchors(explorerBounds);
                ExplorerObserver.Log($"[NoteWindow] RecalculateAnchors executado para nota {_noteId}: _anchorDx={_anchorDx}, _anchorDy={_anchorDy}");
            }

            // Reposiciona a nota mantendo a distância relativa (âncora) do canto superior esquerdo do Explorer
            Left = explorerBounds.Left + _anchorDx;
            Top = explorerBounds.Top + _anchorDy;

            ExplorerObserver.Log($"[NoteWindow] Nota {_noteId} reposicionada para Left={Left}, Top={Top}");

            _isPositioningFromExplorer = false;
        }

        public void RecalculateAnchors(RECT explorerBounds)
        {
            _anchorDx = Left - explorerBounds.Left;
            _anchorDy = Top - explorerBounds.Top;
        }

        public void FlushPendingSave()
        {
            if (_saveTextTimer.IsEnabled)
            {
                _saveTextTimer.Stop();
                SaveText();
            }
            if (_saveFrameTimer.IsEnabled)
            {
                _saveFrameTimer.Stop();
                SaveFrame();
            }
        }

        private void SaveText()
        {
            _note.Text = NoteTextBox.Text;
            NoteStore.Shared.Save(_note);
        }

        private void SaveFrame()
        {
            _note.Frame = new NoteFrame
            {
                X = Left,
                Y = Top,
                W = Width,
                H = Height
            };
            NoteStore.Shared.Save(_note);
        }

        private void NoteWindow_LocationChanged(object? sender, EventArgs e)
        {
            if (!_isLoaded) return;

            // Se o movimento foi manual pelo usuário (não pelo observer do Explorer), recalcula a âncora
            if (!_isPositioningFromExplorer)
            {
                var currentExplorerBounds = NoteWindowManager.Shared.CurrentExplorerBounds;
                if (currentExplorerBounds.HasValue)
                {
                    RecalculateAnchors(currentExplorerBounds.Value);
                }
            }

            // Reseta o timer de salvamento da posição
            _saveFrameTimer.Stop();
            _saveFrameTimer.Start();
        }

        private void NoteWindow_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            if (!_isLoaded) return;

            _saveFrameTimer.Stop();
            _saveFrameTimer.Start();
        }

        private void NoteWindow_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
        {
            FlushPendingSave();
        }

        // Evento de Arrastar a Janela
        private void TitleDragBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ButtonState == MouseButtonState.Pressed)
            {
                DragMove();
            }
        }

        // Editor de Texto Mudou
        private void NoteTextBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (!_isLoaded) return;

            _saveTextTimer.Stop();
            _saveTextTimer.Start();
        }

        // Atalhos de Teclado
        private void NoteTextBox_KeyDown(object sender, KeyEventArgs e)
        {
            // Atalhos para zoom de fonte: Ctrl + "+" e Ctrl + "-"
            if (Keyboard.Modifiers == ModifierKeys.Control)
            {
                if (e.Key == Key.OemPlus || e.Key == Key.Add)
                {
                    AdjustFontSize(2);
                    e.Handled = true;
                }
                else if (e.Key == Key.OemMinus || e.Key == Key.Subtract)
                {
                    AdjustFontSize(-2);
                    e.Handled = true;
                }
            }
        }

        private void AdjustFontSize(double amount)
        {
            double newSize = Math.Clamp(_note.Style.FontSize + amount, 8, 72);
            if (newSize != _note.Style.FontSize)
            {
                _note.Style = new NoteStyle
                {
                    Color = _note.Style.Color,
                    FontID = _note.Style.FontID,
                    FontSize = newSize
                };
                ApplyStyle();
                _saveFrameTimer.Stop(); // Força salvar estilo/frame
                SaveFrame();
            }
        }

        // Troca de Cor pelo Toolbar
        private void ColorButton_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string colorStr && Enum.TryParse(colorStr, out NoteColor color))
            {
                _note.Style = new NoteStyle
                {
                    Color = color,
                    FontID = _note.Style.FontID,
                    FontSize = _note.Style.FontSize
                };
                ApplyStyle();
                SaveFrame(); // Salva estado da nota
            }
        }

        // Botões de Zoom do Toolbar
        private void SizeDownButton_Click(object sender, RoutedEventArgs e) => AdjustFontSize(-2);
        private void SizeUpButton_Click(object sender, RoutedEventArgs e) => AdjustFontSize(2);

        // Ciclar Fontes
        private void FontCycleButton_Click(object sender, RoutedEventArgs e)
        {
            var fonts = Enum.GetValues<NoteFontID>();
            int index = Array.IndexOf(fonts, _note.Style.FontID);
            var nextFont = fonts[(index + 1) % fonts.Length];

            _note.Style = new NoteStyle
            {
                Color = _note.Style.Color,
                FontID = nextFont,
                FontSize = _note.Style.FontSize
            };
            ApplyStyle();
            SaveFrame();
        }

        // Exportar como Texto (.txt)
        private void ExportButton_Click(object sender, RoutedEventArgs e)
        {
            // Cria nome de arquivo sanitizado
            string snippet = NoteStore.MakeSnippet(_note.Text);
            string sanitizedSnippet = Regex.Replace(snippet, @"[\\/:*?""<>|]", ""); // sanitiza caracteres inválidos no Windows
            if (sanitizedSnippet.Length > 50) sanitizedSnippet = sanitizedSnippet.Substring(0, 50);
            if (string.IsNullOrWhiteSpace(sanitizedSnippet) || sanitizedSnippet == "Nota vazia") sanitizedSnippet = "Nota";

            var sfd = new SaveFileDialog
            {
                Filter = "Arquivos de Texto (*.txt)|*.txt|Todos os Arquivos (*.*)|*.*",
                FileName = $"The Styk – {sanitizedSnippet}.txt",
                Title = "Exportar Nota"
            };

            if (sfd.ShowDialog() == true)
            {
                try
                {
                    File.WriteAllText(sfd.FileName, _note.Text, System.Text.Encoding.UTF8);
                }
                catch (Exception ex)
                {
                    MessageBox.Show(this, $"Erro ao exportar nota: {ex.Message}", "Erro", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }

        // Deletar Nota (Mover para lixeira)
        private void DeleteButton_Click(object sender, RoutedEventArgs e)
        {
            var result = MessageBox.Show(this, "Apagar esta nota?", "Confirmar Exclusão", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (result == MessageBoxResult.Yes)
            {
                FlushPendingSave();
                NoteStore.Shared.MoveToTrash(_noteId);
                Close();
            }
        }
    }
}
