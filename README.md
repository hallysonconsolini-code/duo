# Duo

App macOS para rodar vários Claude Code lado a lado, com contas diferentes, e deixar
que eles conversem entre si.

- **Workspaces**: cada aba é uma pasta de projeto.
- **Painéis em grid**: cada painel é um Claude Code (ou o claude.ai) de uma conta. ⌘T abre um
  painel novo na hora, na pasta do workspace.
- **Contas separadas**: cada conta usa seu próprio `CLAUDE_CONFIG_DIR` (login, histórico, config)
  e seu próprio armazenamento de cookies no claude.ai. Por padrão, a Conta 1 usa o `~/.claude`.
- **Painéis que conversam**: o app sobe um servidor MCP local (`duo`) que todo painel recebe
  automaticamente, com estas ferramentas:
  - `list_panes`: lista os painéis e o estado de cada um
  - `send_to_pane`: manda uma mensagem/tarefa para outro painel
  - `read_pane`: lê a última resposta (ou a tela) de outro painel
  - `wait_for_pane`: espera outro painel terminar e devolve a resposta
  - `spawn_pane`: abre um painel novo já com uma tarefa (na mesma conta ou na "outra")

  Exemplo, num painel: *"divida isso em duas partes, abra um painel na outra conta para a
  parte de testes e me traga o resultado"*.
- **Status ao vivo** (trabalhando / pronto / aguardando você) via hooks do Claude Code.
- **Retomada**: ao reabrir o app, cada painel continua a conversa de onde parou.

## Atalhos

| | |
|---|---|
| ⌘T / ⇧⌘T | novo painel (mesma conta / outra conta) |
| ⌘N | abrir pasta como workspace |
| ⌘W | fechar painel |
| ⌘1…⌘9 | focar painel |
| ⌘↩ | zoom no painel |
| ⇧⌘[ / ⇧⌘] | workspace anterior / próximo |

Clique com o botão direito no cabeçalho de um painel para encaminhar a última resposta
dele para outro painel.

## Compilar

Requer macOS 14+ e as Command Line Tools (Xcode não é necessário).

```bash
./scripts/install.sh     # compila e instala/atualiza em /Applications (fecha e reabre o Duo)
./scripts/make-dmg.sh    # gera build/Duo-<versão>.dmg para instalar em outro Mac
```

## Como funciona

Cada painel roda `claude --mcp-config … --settings …` num shell de login. Os arquivos ficam em
`~/Library/Application Support/Duo/run/<painel>/`: o MCP aponta para `http://127.0.0.1:<porta>/mcp`
e os hooks fazem `curl` para `/hook/<evento>`. A porta e o token mudam a cada abertura do app,
e só conexões locais com o token são aceitas. As ferramentas `mcp__duo` já vêm liberadas
nas permissões desses painéis.
