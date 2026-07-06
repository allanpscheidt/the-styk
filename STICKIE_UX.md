# StickIE — Auditoria de UX

Contrato-base: `ARCHITECTURE.md`. Princípio: resolver cada caso-limite com o mínimo de mecânica nova. Itens marcados **[NOVO]** exigem código além do contrato; o resto é decisão de comportamento dentro do que já existe.

---

## 1. Casos-limite e resolução mínima

### 1.1 Primeira execução sem permissão de automação
- O prompt do sistema (TCC) aparece no **primeiro poll** — ou seja, na primeira vez que o Finder ficar frontal após o launch, antes mesmo de o usuário criar nota. Isso é bom: o `NSAppleEventsUsageDescription` (ver microcopy) explica o porquê no próprio diálogo do sistema.
- Se negar (`-1743`): o contrato já cobre o alerta único. Falta o caminho de volta. **[NOVO — mínimo]** O alerta ganha botão "Abrir Ajustes" que abre `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`; e enquanto a permissão estiver negada, o primeiro item do menu vira **"Permitir acesso ao Finder…"** (mesma URL). Um item de menu + uma flag — sem tela de onboarding.
- Sem isso, o item desabilitado "Abra uma pasta no Finder…" mente para o usuário (ele abriu a pasta e nada acontece).

### 1.2 Primeira execução: app "invisível"
- App de barra de menus sem Dock: o usuário abre o StickIE e **nada visível acontece**. Trava real de descoberta.
- **[NOVO — mínimo]** Alerta único no primeiro launch (flag em UserDefaults, mesmo padrão do `-1743`): título "O StickIE está na barra de menus", texto curto (ver §2). Nada de tour, nada de janela de boas-vindas.

### 1.3 Usuário cria nota e troca de pasta antes de digitar
- Reconcile fecha o painel com `flushPendingSave` → nota vazia persiste com snippet "Nota vazia" e reaparece quando ele voltar. **Manter assim, sem mecânica extra.** Apagar em silêncio nota "vazia" destrói confiança (o usuário criou de propósito); o snippet-fallback já torna a nota localizável pelo menu.

### 1.4 Nota em pasta de drive externo desmontado
- O menu já valida a pasta → item vira "Pasta não encontrada" (desabilitado). Correto: **não apagar nada automaticamente** — o drive volta e as notas voltam junto, de graça, porque a âncora é o caminho em `/Volumes/...`.
- Recuperação do texto sem o drive: o submenu da nota já tem "Exportar…". Suficiente para v1. (Re-ancorar nota em outra pasta = feature v1.1, não adicionar agora.)

### 1.5 Pasta renomeada ou movida
- As notas somem em silêncio (âncora por caminho). Aceitar em v1 — rastrear por FSEvents/bookmark é mecânica grande demais.
- O menu vira a rede de segurança: a pasta antiga continua listada, com "Pasta não encontrada" e as notas com "Exportar…"/"Apagar…". O usuário nunca *perde* texto, só a âncora. Documentar no About (uma linha: "as notas grudam no caminho da pasta").

### 1.6 Duas janelas do Finder
- O script já lê só a janela frontal — comportamento coerente com a promessa do app ("a nota da pasta que você está vendo"). Trocar de janela com ⌘\` fecha os painéis com flush: **zero perda de texto**, nenhuma mecânica extra.
- Ponto verificado: o painel é `nonactivating`, então clicar/digitar na nota **não** ativa o StickIE — o Finder segue frontal e o timer continua. Sem bug de "nota some quando clico nela".

### 1.7 Stage Manager / Spaces / fullscreen / monitor removido
- `.moveToActiveSpace + .fullScreenAuxiliary` cobre Spaces e Finder em tela cheia; painéis `.floating` sobrevivem ao Stage Manager.
- Frame salvo fora de qualquer tela (monitor desconectado): o contrato já reposiciona em `NSScreen.main.visibleFrame`.
- **[NOVO — 1 linha]** A cascata do `suggestedFrame()` (+24 pt por nota) deve dar a volta (módulo) dentro de `visibleFrame` — com 20 notas, sem isso, a nota nova nasce fora da tela.

### 1.8 VoiceOver e teclado (mínimo obrigatório — não é opcional)
- A barra no hover (alpha 0→1) é invisível para VoiceOver se os botões forem escondidos por alpha. Regra: **animar só o alpha, nunca `isHidden`**, e todo botão com `setAccessibilityLabel` (strings no §2). O VoiceOver então encontra os controles mesmo sem hover.
- `NSStatusItem.button` → label "StickIE". `NSTextView` → label "Texto da nota".
- Alertas (`NSAlert`) e menu já são acessíveis de graça pelo AppKit — não tocar.

### 1.9 Digitação em risco (debounce 1,5 s)
- Coberto: fechar painel, trocar de pasta e `applicationWillTerminate` fazem flush. Único buraco é force-quit/crash (perde ≤1,5 s de digitação) — aceitável, não adicionar autosave mais agressivo.

### 1.10 Desktop e janelas especiais do Finder
- Desktop sem janela aberta, busca do Finder, Recentes, AirDrop: o script devolve `""` → nenhuma nota. Coerente. O item desabilitado do menu ("Abra uma pasta…") já explica o estado. Nada a fazer.

---

## 2. Microcopy final (pt-BR)

Tom: direto e caloroso, sem jargão, sem "por favor", sem exclamação em série. "Você" implícito.

### Info.plist
| Chave | Texto |
|---|---|
| `NSAppleEventsUsageDescription` | `O StickIE pergunta ao Finder qual pasta está aberta, para mostrar cada nota no lugar certo.` |
| `CFBundleName` | `StickIE` |
| `NSHumanReadableCopyright` | `© 2026 Allan Pscheidt` |

### Menu da barra
| Contexto | Texto |
|---|---|
| Criar (habilitado) | `Nova nota nesta pasta` |
| Criar (sem pasta frontal) | `Abra uma pasta no Finder para criar uma nota` |
| Permissão negada (substitui o item acima) | `Permitir acesso ao Finder…` |
| Cabeçalho | `Notas (N)` |
| Sem nenhuma nota (cabeçalho) | `Nenhuma nota ainda` |
| Item de pasta (submenu) | caminho abreviado com `~` (contrato) |
| Abrir pasta | `Abrir pasta no Finder` |
| Pasta inválida/ausente | `Pasta não encontrada` |
| Exportar nota | `Exportar…` |
| Apagar nota | `Apagar…` |
| Sobre | `Sobre o StickIE` |
| Sair | `Sair do StickIE` |

### Alertas
**Primeiro launch** (uma vez):
- Título: `O StickIE está na barra de menus`
- Texto: `Abra uma pasta no Finder e clique no ícone de nota lá em cima para criar sua primeira nota. Ela gruda na pasta: some quando você sai e volta quando você volta.`
- Botão: `Entendi`

**Automação negada** (`-1743`, uma vez):
- Título: `O StickIE precisa falar com o Finder`
- Texto: `Sem essa permissão, o StickIE não sabe qual pasta está aberta. Ative em Ajustes do Sistema → Privacidade e Segurança → Automação → StickIE → Finder.`
- Botões: `Abrir Ajustes` (default) · `Agora não`

**Apagar nota** (painel e menu, mesmo alerta):
- Título: `Apagar esta nota?`
- Texto: `Ela some da pasta e não dá para desfazer.`
- Botões: `Apagar` (destrutivo) · `Cancelar` (default/Esc)

### Barra de ferramentas da nota — tooltips = labels de VoiceOver
| Controle | Texto |
|---|---|
| Bolinha amarela | `Amarelo` |
| Bolinha rosa | `Rosa` |
| Bolinha azul | `Azul` |
| Bolinha verde | `Verde` |
| Bolinha laranja | `Laranja` |
| Bolinha roxa | `Roxo` |
| `A−` | `Diminuir letra` |
| `A+` | `Aumentar letra` |
| `Aa` | `Trocar fonte` |
| Share | `Exportar nota` |
| Lixeira | `Apagar nota` |
| Status item (VoiceOver) | `StickIE` |
| Campo de texto (VoiceOver) | `Texto da nota` |

`Theme.label(_:)` usa os mesmos seis nomes de cor acima.

### Outras strings
| Contexto | Texto |
|---|---|
| Snippet de nota vazia | `Nota vazia` |
| Nome de arquivo exportado | `StickIE – <snippet>.txt` · fallback `StickIE – Nota.txt` |
| About (Credits, uma linha) | `Notas que grudam nas suas pastas. As notas seguem o caminho da pasta: se você renomear ou mover a pasta, encontre a nota pelo menu e exporte o texto.` |

---

## 3. Veredito de fluxo: criar → editar → sair → voltar → exportar

**O ciclo central funciona sem atrito.** Criar pelo menu, painel nasce na pasta certa via reconcile; editar com autosave; sair da pasta fecha com flush (zero perda); voltar reabre no mesmo lugar; exportar via share picker padrão. Nada a mudar no miolo.

**Onde um usuário real trava, em ordem:**

1. **Minuto zero.** Abre o app e não acontece nada visível. Sem o alerta de primeiro launch (§1.2), metade dos usuários acha que o app não abriu. É a única adição de UI realmente necessária.
2. **Permissão negada sem volta.** Quem nega o prompt do sistema fica com um app morto e nenhum caminho de recuperação dentro do app (§1.1). Botão "Abrir Ajustes" + item de menu resolvem.
3. **"Quero olhar a nota enquanto escrevo um e-mail."** Ao ativar qualquer outro app, todas as notas somem — é a alma do produto, mas vai ser o pedido nº 1 dos usuários ("fixar nota"). Não resolver em v1; anotar como candidato a v2 (pin por nota). O export cobre o caso de levar o texto para fora.
4. **Renomear/mover pasta** = notas órfãs em silêncio (§1.5). A rede de segurança do menu + "Exportar…" evita perda de texto; a linha no About ajusta a expectativa.
5. **Descoberta da barra de ferramentas.** Ela só aparece no hover — usuário de trackpad descobre rápido; VoiceOver só funciona se os botões nunca forem `isHidden` (§1.8). Sem custo extra, só disciplina de implementação.

**Resumo:** com três adições mínimas (alerta de primeiro launch, botão/item "Abrir Ajustes" para permissão, wrap da cascata) e as labels de acessibilidade, o fluxo v1 está redondo. Todo o resto é decisão de comportamento já compatível com o contrato.
