# The Styk

<p align="center">
  <img src="assets/logo.png" width="128" alt="The Styk Logo" /><br>
  <sub>
    <b>Versões:</b> macOS (Apple Silicon 11+ / Intel 10.15+) | Windows 10/11 | Linux (GNOME/Nautilus)<br>
    <b>Idiomas:</b> Português (Brasil), English, Deutsch, Français, 日本語, 简体中文
  </sub>
</p>

Notas digitais que moram dentro das suas pastas.

O The Styk é um programa minimalista que mantém notas digitais ancoradas às suas pastas. A nota flutua na tela enquanto você está na pasta onde a criou (Finder no macOS ou File Explorer no Windows) — saia da pasta, ela some; volte, ela reaparece.

## Instalação

### macOS
Baixe o The Styk para macOS em https://setor101.com.br/apps/styk ou na página de [Releases](https://github.com/allanpscheidt/the-styk/releases) e arraste-o para a sua pasta de Aplicativos, então clique duas vezes no ícone para iniciá-lo.

> [!NOTE]
> **Aviso de Bloqueio do macOS (Gatekeeper)**
>
> Caso apareça o aviso "A Apple não pôde verificar se o item...", isso ocorre devido à exigência da Apple de pagamento de taxas anuais por parte dos desenvolvedores para assinar digitalmente o aplicativo. Como o The Styk é um projeto gratuito e de código aberto, acreditamos que essa exigência financeira não é justa para desenvolvedores independentes.
> 
> Para abrir o aplicativo mesmo assim:
> 1. Tente abrir o app uma vez para gerar o aviso e feche-o.
> 2. Acesse **Ajustes do Sistema** > **Privacidade e Segurança** no seu Mac.
> 3. Role até a seção **Segurança** e clique no botão **Abrir Mesmo Assim** logo abaixo da mensagem sobre o `The Styk.app`.
> 4. Insira sua senha ou use o Touch ID para confirmar.

### Windows
Baixe a versão mais recente de `TheStyk-Windows-x64.exe` na página de [Releases](https://github.com/allanpscheidt/the-styk/releases) e execute-a para começar a ancorar notas às pastas do File Explorer.

### Linux
Para rodar o The Styk no Linux (especialmente em ambientes GNOME/Nautilus):

1. **Instale as Dependências do Sistema**:
   - **Ubuntu/Debian**:
     ```bash
     sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-appindicator3-0.1
     ```
   - **Fedora**:
     ```bash
     sudo dnf install python3-gobject gtk3 libappindicator-gtk3
     ```
2. **Execute o Aplicativo**:
   Navegue até a pasta `TheStyk-Linux` e execute o script de inicialização:
   ```bash
   ./run.sh
   ```

## Como Usar

O The Styk coloca um ícone de nota no lado direito da sua barra de menus. Clique no ícone para exibir o menu. A partir daqui, você pode escolher **"Nova nota nesta pasta"** para criar uma nota. Escreva nele; a nota é salva automaticamente.

### Barra de Menus
O menu da barra de status lista todas as notas, agrupadas por pasta. Clique em qualquer nota para ir direto para essa pasta no Finder, exportá-la ou apagá-la.

### Interação com as Notas
Passe o mouse sobre uma nota para revelar sua barra de ações. A partir dela, você pode:
- Alterar as cores da nota.
- Ajustar o tamanho da fonte (A− / A+) e o estilo da fonte (Aa).
- Compartilhar a nota (via AirDrop, Mensagens, Mail, etc.).
- Apagar a nota.

Arraste a nota pelo fundo para movê-la, ou pelas bordas para redimensioná-la. Dentro da nota, use `⌘ +` e `⌘ −` para ajustar rapidamente o tamanho do texto.

### Configurações
No menu da barra, abra as Configurações para configurar:
- **Idioma**: Alterne entre Português (Brasil), Inglês, Chinês, Japonês, Alemão ou Francês.
- **Permissão do Finder**: Gerencie as permissões de automação do Apple Events necessárias para rastrear a janela ativa do Finder.
- **Iniciar junto com o sistema**: Escolha se o The Styk deve abrir automaticamente ao iniciar o Mac.
- **Backups**: Configure backup automático local diário ou exporte/restaure todas as notas manualmente.

## FAQ (Perguntas Frequentes)

### O app precisa de permissões especiais?
Sim. Na primeira execução, o macOS perguntará se o The Styk pode controlar o Finder. Isso é necessário para que o app detecte qual pasta está ativa e exiba suas respectivas notas. Se você negar por engano, pode re-solicitar o aviso via Configurações -> botão "Pedir permissão do Finder...".

### O que acontece quando eu apago uma nota?
Apagar é totalmente reversível. As notas apagadas vão para a Lixeira interna do app (acessível pela barra de menus) e ficam lá por 5 dias antes de serem removidas definitivamente.

### O que acontece se eu mover, renomear ou apagar uma pasta?
- **Pastas Movidas/Renomeadas**: O The Styk usa bookmarks do macOS, então as notas seguem a pasta automaticamente mesmo se você a renomear ou mover de disco.
- **Pastas Apagadas**: As notas não são perdidas; elas ficam na seção "Notas órfãs" do menu, onde você pode reancorá-las, exportá-las ou movê-las para a Lixeira.

### O app funciona no macOS 10.x?
A versão principal para Apple Silicon exige o macOS 11 (Big Sur) ou posterior. No entanto, existe uma versão Intel legada disponível que roda no macOS 10.15 (Catalina) e posteriores.

### Como o The Styk é diferente das notas autoadesivas padrão?
Diferente dos apps de notas comuns onde as notas poluem sua mesa indefinidamente, o The Styk ancora as notas contextualmente a pastas específicas. Elas só aparecem quando você realmente abre e visualiza aquela pasta no Finder (macOS) ou File Explorer (Windows).
