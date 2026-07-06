# Política de Privacidade — The Styk

**Última atualização: 6 de julho de 2026**

## Resumo em uma linha

O The Styk não coleta, não transmite e não compartilha nenhum dado. Tudo fica no seu Mac.

## O que o app guarda (e onde)

O The Styk guarda apenas o que é necessário para funcionar, **exclusivamente no seu
computador**, na pasta `~/Library/Application Support/The Styk/`:

- o texto das suas notas, com cor, fonte, tamanho e posição na tela;
- o caminho das pastas onde você criou notas (e um marcador do macOS que permite
  seguir a pasta se ela for movida);
- notas apagadas recentemente (ficam na Lixeira do app por 5 dias e depois são
  removidas de forma definitiva);
- backups locais em .zip, somente se você ativar essa opção — o backup automático
  fica na própria pasta de dados do app (`Backups/`, mantém os 7 mais recentes);
  o backup manual é salvo no local que você escolher.

O app **não tem acesso à internet**: não existe nenhum código de rede, telemetria,
estatística de uso, conta de usuário ou serviço de terceiros. O desenvolvedor não
recebe absolutamente nada — nem dados, nem métricas, nem relatórios de erro.

## Permissões do macOS

- **Automação (Finder):** usada unicamente para perguntar ao Finder qual pasta está
  aberta e a posição da janela, para mostrar as notas certas no lugar certo. O app
  não lê nomes de arquivos, conteúdo de arquivos nem qualquer outra coisa dentro
  das pastas.
- **Iniciar junto com o sistema (opcional):** só se você ativar nas Configurações.

## Compartilhamento

Nada sai do app sem uma ação sua. Ao usar "Exportar" (AirDrop, Mensagens, Mail…),
o conteúdo da nota é enviado como texto puro para o destino **que você escolheu** —
a partir daí, ele está fora do controle do app, como qualquer arquivo que você envia.
Para o envio funcionar, o app grava uma cópia temporária da nota na pasta temporária
do sistema — ela é apagada automaticamente minutos após o envio (e qualquer resquício,
na próxima abertura do app).

## Seus direitos (LGPD/GDPR)

Como nenhum dado pessoal chega ao desenvolvedor, você exerce os direitos aplicáveis
diretamente no app: **acesso** (abrir e ler suas notas quando quiser),
**portabilidade** (Exportar, em texto puro legível por qualquer programa),
**correção** (editar a nota) e **apagamento** (apagar definitivamente na Lixeira —
ou remover a pasta `~/Library/Application Support/The Styk/` para eliminar tudo).
Desinstalar o app não apaga essa pasta; remova-a manualmente se quiser eliminar
todos os dados.

## Segurança

Os dados ficam em arquivos no seu Mac, protegidos pelas defesas do próprio sistema.
Mensagens de diagnóstico do app (sem conteúdo de notas) ficam apenas no log local
do macOS, gerenciado pelo sistema.
Recomendamos manter o **FileVault** ativado (criptografia de disco do macOS) — é ele
que protege suas notas, como protege o resto dos seus arquivos. Os backups em .zip
não são criptografados pelo app; guarde-os como guardaria qualquer documento seu.

## Crianças

O The Styk não coleta dado de ninguém — inclusive de crianças.

## Mudanças nesta política

Se esta política mudar, a nova versão acompanhará o app, com a data de atualização
no topo. Como o app não tem rede, nenhuma mudança pode acontecer "por baixo dos panos".

## Contato

Prof. Dr. Allan Pscheidt — alpscheidt@gmail.com · [allanpscheidt.com.br](https://allanpscheidt.com.br)
