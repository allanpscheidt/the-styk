# Segurança do The Styk

## Bloqueio por senha

A senha controla o acesso às notas dentro do aplicativo. Os arquivos locais e os
backups continuam em texto legível, com proteção das permissões do sistema e da
criptografia de disco quando ativada.

Quando existe uma senha, cada abertura do app começa bloqueada. A autenticação
permanece somente na memória do processo. O app bloqueia novamente ao encerrar,
ao suspender o computador, ao bloquear a tela, ao trocar de usuário e após cinco
minutos sem interação de teclado, clique ou rolagem no The Styk.

Durante o bloqueio, a galeria fecha, as janelas de notas fecham e o menu oferece
desbloqueio e saída. Leitura de notas, trechos do índice e alterações no
armazenamento exigem uma sessão autenticada. Exportar, fazer backup, restaurar,
mover para a lixeira, recuperar da lixeira, apagar definitivamente, esvaziar a
lixeira e alterar a senha solicitam a senha novamente. Cada autorização vale
para uma operação, expira em 60 segundos e perde validade no bloqueio.

O backup automático fica suspenso quando existe uma senha configurada. O backup
manual continua disponível após autenticação. A retenção da lixeira respeita o
bloqueio e retoma a limpeza quando o usuário desbloqueia o app.

## Restauração de backups

A restauração prepara os dados em um diretório privado e valida o índice, os
identificadores, as notas referenciadas e a lixeira antes da troca do
armazenamento. Uma falha de validação preserva os dados atuais. A troca mantém
o armazenamento anterior disponível para recuperação até concluir a gravação.
Se o próprio rollback falhar, o app informa que os dados exigem revisão e
mostra o diretório privado de recuperação. Essa situação recebe uma mensagem
específica e mantém as cópias disponíveis para conferência.

Os backups novos incluem notas, índice, lixeira e marcadores de pastas. Um
backup antigo com referências a arquivos de lixeira ausentes precisa de revisão
e será rejeitado pela validação.

O leitor de ZIP aceita arquivos comuns e diretórios com compressão store ou
deflate. Os limites de entrada são 64 MiB de ZIP, 128 MiB descompactados,
5 MiB por arquivo, 20.010 entradas, três níveis de caminho e razão de compressão
de até 200. A extração tem prazo de 30 segundos e verifica espaço disponível.
As notas mantêm o limite de 2 MiB por arquivo e 200 mil caracteres de texto.
Arquivos especiais, links, caminhos absolutos, travessia de diretórios,
duplicatas e conteúdo com verificação de integridade inválida são rejeitados.

## Pastas e compartilhamento

Galeria e menu usam a mesma validação para abrir pastas. O caminho deve apontar
para um diretório existente comum. Aplicativos, pacotes, documentos, aliases e
caminhos com componentes que sejam links são rejeitados. Uma pasta ausente pode
continuar registrada como âncora de uma nota órfã.

As cópias temporárias de exportação ficam em `TheStyk-Exports`, dentro da pasta
temporária do sistema. O diretório usa permissão 0700 e os arquivos usam 0600.
Cancelar, concluir ou falhar no compartilhamento remove a cópia. Um prazo de
15 minutos cobre serviços que deixam de informar a conclusão. A próxima
abertura remove todas as sobras próprias, inclusive as criadas há poucos
segundos e os exports reconhecidos da versão anterior.
Bloquear o aplicativo também cancela os painéis pendentes e remove suas cópias.

## Linux e Windows

No Linux, diretórios de dados usam 0700 e arquivos usam 0600. O armazenamento
ajusta permissões de arquivos existentes e verifica proprietário, tipo e
links antes de acessar os dados. Descritores de diretórios mantêm as operações
ancoradas no armazenamento validado.

Sem evidência da janela ativa, inclusive em sessões Wayland sem integração
compatível, o observador oculta as notas e limpa o contexto anterior. A
exibição automática depende de uma integração capaz de identificar o foco.

No Windows, o observador deixa de registrar atividade e caminhos do Explorer
em `debug.log`. Um log existente de versões anteriores permanece disponível
para o usuário revisar ou excluir.

## Publicação de versões

As ações do GitHub usam identificadores completos de commits. Dependabot abre
propostas de atualização semanalmente para revisão. Somente a etapa de
publicação recebe permissão de escrita no conteúdo do repositório.

As etapas de compilação geram atestações de procedência dos arquivos. A etapa
de publicação verifica a assinatura, o repositório, o workflow, o commit e a
referência de origem antes de criar a versão.

A aplicação completa dessa proteção também requer configurações no GitHub:

- Configure revisores obrigatórios no ambiente `release`.
- Restrinja nesse ambiente as referências permitidas para publicação.
- Proteja as tags `v*` com regras que restrinjam criação, alteração e exclusão.
- Revise as propostas de atualização das ações antes de incorporá-las.

O arquivo do workflow referencia esse ambiente. Revisores e regras de tags
dependem das configurações do repositório e precisam de verificação separada.

## Verificação

Os testes de regressão usam armazenamento temporário, sem acessar notas reais.
A validação abrange bloqueio e autorizações, restauração inválida, limites de
ZIP, permissões Linux, perda de evidência de foco, abertura de pastas e limpeza
de exportações. Os workflows de verificação também compilam o aplicativo para
macOS e Windows.

Os relatos 8 e 9 descrevem a mesma falha de abertura de pastas e recebem uma
única correção.
