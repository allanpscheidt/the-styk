# The Styk (Versão Microsoft Windows)

Esta é a versão para Microsoft Windows do **The Styk** (StickIE), portada nativamente da versão macOS (Swift/AppKit) para **C# / WPF** (Windows Presentation Foundation) sobre o **.NET 8.0-windows**.

As notas digitais são vinculadas dinamicamente às pastas do Windows Explorer, aparecendo na tela apenas enquanto a pasta na qual foram criadas está em foco/primeiro plano.

---

## 🚀 Requisitos e Configuração

- **Sistema Operacional:** Windows 10 ou Windows 11 (64-bit).
- **SDK Necessário:** [.NET 8.0 SDK](https://dotnet.microsoft.com/download) ou superior.
- **IDE Recomendada:** Visual Studio 2022 (com a carga de trabalho de Desenvolvimento do Windows Desktop instalada) ou VS Code com extensões C#.

---

## 🛠️ Como Compilar e Executar

### Opção 1: Via Terminal (CLI)
1. Abra o terminal (Command Prompt ou PowerShell) no diretório deste projeto (`TheStyk-Windows`).
2. Para compilar e executar o projeto diretamente:
   ```bash
   dotnet run --project TheStyk-Windows/TheStyk-Windows.csproj
   ```
3. Para gerar um executável de produção otimizado e autossuficiente (sem precisar do runtime .NET instalado na máquina do usuário):
   ```bash
   dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishReadyToRun=true
   ```
   O arquivo executável único `.exe` será gerado na pasta `TheStyk-Windows/bin/Release/net8.0-windows/win-x64/publish/`.

### Opção 2: Via Visual Studio
1. Dê um duplo-clique no arquivo `TheStyk-Windows.sln` para abrir o projeto no Visual Studio.
2. Certifique-se de que a configuração está definida como **Debug** ou **Release** e aperte **F5** (ou clique em **Start**) para compilar e executar.

---

## 📂 Estrutura de Arquivos e Código

O projeto segue uma arquitetura idêntica à do macOS, mas adaptada para as APIs nativas do Windows:

- **[TheStyk-Windows.sln](TheStyk-Windows.sln):** Solução do Visual Studio que agrupa os arquivos.
- **[TheStyk-Windows.csproj](TheStyk-Windows/TheStyk-Windows.csproj):** Arquivo do projeto. Habilita o WPF, Windows Forms (para o System Tray `NotifyIcon`) e adiciona as referências COM das bibliotecas `SHDocVw` e `Shell32` usadas para inspecionar o Windows Explorer.
- **[App.xaml / App.xaml.cs](TheStyk-Windows/App.xaml.cs):** Ponto de entrada que inicia o monitoramento em segundo plano e garante o salvamento atômico das notas ao fechar o app.
- **[Models.cs](TheStyk-Windows/Models/Models.cs):** Definição dos modelos de dados (`Note`, `NoteStyle`, `NoteFrame`, `IndexEntry` e `TrashEntry`).
- **[NoteStore.cs](TheStyk-Windows/Models/NoteStore.cs):** Serviço de banco de dados baseado em arquivos JSON (compatível 1:1 com o macOS). Gerencia leituras seguras (limite de 2MB, clamping de fontes e frames), salvamentos atômicos e a lixeira interna (exclusão após 5 dias).
- **[ExplorerObserver.cs](TheStyk-Windows/System/ExplorerObserver.cs):** Usa APIs Win32 (`GetForegroundWindow`, `GetWindowRect`) e a API COM do Windows Explorer para descobrir qual pasta está aberta e obter suas coordenadas na tela.
- **[NoteWindowManager.cs](TheStyk-Windows/System/NoteWindowManager.cs):** Gerencia a exibição e posicionamento das notas flutuantes de forma a acompanharem a janela ativa do Explorer.
- **[NoteWindow.xaml / NoteWindow.xaml.cs](TheStyk-Windows/UI/NoteWindow.xaml.cs):** Janela do Post-It flutuante. Transparente, sem bordas do sistema, com sombra nativa e cantos arredondados. Implementa a barra de ferramentas no hover para trocar cores, ajustar fontes (Aa, A-, A+), atalhos `Ctrl +` / `Ctrl -`, exportar e apagar.
- **[TrayController.cs](TheStyk-Windows/UI/TrayController.cs):** Controlador do ícone da bandeja do sistema (System Tray). Monta menus de forma dinâmica (agrupados por pasta), permitindo restaurar notas da lixeira ou re-ancorar notas órfãs usando um seletor de diretórios nativo.
- **[Theme.cs](TheStyk-Windows/UI/Theme.cs):** Definição da paleta de cores pastel e mapeamento de fontes nativas do Windows (Segoe UI, Consolas, Georgia, Segoe Print).

---

## 💾 Onde os Dados são Armazenados?

As notas são guardadas na pasta local do usuário em formato JSON:
- **Caminho:** `%APPDATA%\The Styk\` (geralmente resolve para `C:\Users\<NomeUsuario>\AppData\Roaming\The Styk`).
  - `index.json` contém a versão e o índice de todas as notas e lixeira.
  - `notes/` pasta com as notas completas como arquivos `<UUID>.json`.
  - `trash/` pasta da lixeira contendo as notas excluídas.
