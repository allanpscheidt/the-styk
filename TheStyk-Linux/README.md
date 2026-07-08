# The Styk (Versão Linux)

Esta é a versão para Linux do **The Styk** (StickIE), portada nativamente em **Python 3 + GTK 3 (PyGObject)**.

As notas digitais são vinculadas dinamicamente às pastas do seu gerenciador de arquivos (Nautilus no GNOME, Dolphin no KDE, etc.), aparecendo na tela apenas quando a pasta correspondente está ativa/focada.

---

## 🚀 Requisitos e Instalação

Como o GTK e o D-Bus utilizam bibliotecas compartilhadas do sistema, a forma recomendada de instalar as dependências é através do gerenciador de pacotes da sua distribuição.

### Ubuntu / Debian / Pop!_OS / Linux Mint
```bash
sudo apt update
sudo apt install python3 python3-pip python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-appindicator3-0.1
pip3 install -r requirements.txt
```

### Fedora / Red Hat
```bash
sudo dnf install python3 python3-pip python3-gobject gtk3 libappindicator-gtk3
pip3 install -r requirements.txt
```

### Arch Linux
```bash
sudo pacman -S python python-pip python-gobject gtk3 libappindicator-gtk3
pip3 install -r requirements.txt
```

---

## 🛠️ Como Executar

1. Navegue até o diretório do projeto:
   ```bash
   cd TheStyk-Linux
   ```
2. Execute o script principal:
   ```bash
   ./run.sh
   ```
   ou diretamente com python:
   ```bash
   python3 src/main.py
   ```

---

## 📂 Estrutura de Arquivos e Código

O projeto segue a mesma arquitetura modular das versões macOS e Windows:

- **`src/models.py`:** Definição das classes de dados (`Note`, `NoteStyle`, `NoteFrame`, `IndexEntry` e `TrashEntry`).
- **`src/note_store.py`:** Serviço de persistência baseado em arquivos JSON compatível 1:1 com macOS/Windows. Armazena os dados em `~/.config/the-styk/`.
- **`src/theme.py`:** Definição da paleta de cores pastel e fontes padrão do Linux.
- **`src/observer.py`:** Monitora o foco das janelas e a navegação no Nautilus/Dolphin via barramento D-Bus (`org.freedesktop.FileManager1`).
- **`src/window_manager.py`:** Controla as janelas flutuantes das notas em GTK (janelas transparentes, sem decoração/borda, nível superior/always-on-top).
- **`src/tray.py`:** Controlador do menu da bandeja do sistema (System Tray) usando AppIndicator ou GTK StatusIcon.
- **`src/main.py`:** Inicialização do loop principal do GTK e orquestração do sistema.

---

## 💾 Armazenamento dos Dados

As notas são salvas de forma idêntica ao macOS e Windows no seguinte caminho padrão de configuração do Linux:
- `~/.config/the-styk/`
  - `index.json`
  - `notes/<UUID>.json`
  - `trash/`

Isso permite que você sincronize ou mova suas notas entre diferentes sistemas operacionais sem perda de dados!
