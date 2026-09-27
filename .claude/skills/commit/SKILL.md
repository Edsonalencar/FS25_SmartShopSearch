---
name: commit
description: Cria commits git em PT-BR seguindo o padrão Solarz (tipo(escopo) descrição no imperativo), com agrupamento estratégico de arquivos, plano de aprovação antes de executar, e sem co-autoria do Claude. Use when the user pedir "commitar alterações", "criar commit", "fazer commit", "commit das mudanças", "commitar isso", "commit", "commit changes", "create commit", ou similares. Do NOT use for git push, abrir PR, criar branch, stash, rebase, cherry-pick ou outras operações git que não sejam criação de commit.
license: CC-BY-4.0
metadata:
  author: Edson Alencar
  version: 1.0.0
---

# Commit (Solarz)

Cria commits git para as alterações da sessão atual, agrupando arquivos por camada lógica, exigindo aprovação do usuário antes de executar, e nunca atribuindo autoria ao Claude.

## Hard rules

- **NUNCA** adicione `Co-Authored-By`, `Generated with Claude`, ou qualquer menção ao Claude/Anthropic na mensagem.
- **NUNCA** use `git add -A`, `git add .`, ou `git add --all`. Sempre adicione arquivos específicos por nome.
- **NUNCA** use `--no-verify` para pular hooks. Se um hook falhar, corrija o problema e crie um NOVO commit (não amend).
- **NUNCA** execute `git commit` sem ter apresentado o plano e recebido confirmação explícita do usuário.
- **NUNCA** misture em um mesmo commit: mudanças funcionais com refactor, migrations com lógica de negócio, ou testes com código de produção de camadas diferentes.

## Process

### Passo 1: Coletar contexto

Execute em paralelo (um único bloco com múltiplas chamadas Bash):

- `git status --short` — arquivos modificados/staged/untracked
- `git diff` — mudanças não staged
- `git diff --staged` — mudanças já staged
- `git log --oneline -10` — estilo dos commits recentes do repo

Se não houver mudanças (nenhum arquivo modificado e nenhum untracked), pare e avise o usuário. Não crie commit vazio.

### Passo 2: Auto-detectar contexto sensível

Antes de planejar, varra os arquivos modificados/untracked e:

- **Arquivos sensíveis**: se houver `.env`, `.env.*`, `credentials.json`, `*.pem`, `*.key`, `id_rsa*`, ou qualquer arquivo que aparente conter segredo, **destaque ao usuário** e pergunte se realmente deve incluir antes de adicionar ao plano. Por padrão, exclua do agrupamento.
- **Hooks pre-commit**: se existir `.pre-commit-config.yaml`, `.husky/`, ou `lint-staged.config.*`, mencione no plano que hooks serão executados — para o usuário não se surpreender se a primeira tentativa falhar.

### Passo 3: Detectar tipo/escopo automaticamente por path

Use os paths dos arquivos para sugerir o **tipo** e **escopo** de cada commit. Sinais determinísticos:

| Path / padrão                                       | Tipo sugerido | Escopo (exemplo)                         |
| --------------------------------------------------- | ------------- | ---------------------------------------- |
| `src/main/resources/db/migration/**`                | `migration`   | módulo afetado pela tabela               |
| `**/model/**`, `**/entity/**`, `@Entity`            | `feat` ou `refactor` | nome da entidade                  |
| `**/*Controller.java`, `**/*Resource.java`          | `feat` ou `fix` | módulo do controller                   |
| `**/*Service.java`, `**/*UseCase.java`, `**/handlers/**` | `feat`, `fix` ou `refactor` | feature/domínio          |
| `**/*Repository.java`, `**/*Dao.java`               | `refactor` ou `feat` | módulo de dados                     |
| `src/test/**`, `**/*Test.java`, `**/*IT.java`       | `test`        | feature testada                          |
| `CLAUDE.md`, `**/*.md`, `docs/**`                   | `docs`        | módulo documentado                       |
| `application.properties`, `pom.xml`, `.github/**`, configs | `chore` | infra, ci, deps, config             |
| `**/spec/**`, `**/features/FEAT-*.md`               | `spec`        | feature especificada                     |

Quando houver ambiguidade entre `feat` e `refactor`: se o diff **adiciona** capabilidade nova, é `feat`; se **reorganiza** sem mudar comportamento, é `refactor`.

### Passo 4: Planejar commits estrategicamente

Agrupe arquivos contando uma história coerente. Cada commit deve poder ser lido, entendido e revertido isoladamente. Use esta ordem como referência (não como regra cega):

1. **Infra e configuração** — configs, dependências, env
2. **Migrações e schema** — flyway, mudanças em entidades/models
3. **Domínio e negócio** — services, use cases, handlers
4. **Camada de dados** — repositories, queries, DTOs
5. **API e apresentação** — controllers, rotas, filtros
6. **Testes** — de preferência junto com o código que testam, ou separado se cobrirem múltiplas camadas
7. **Ajustes gerais** — refactors menores, typos, dead code, docs

### Passo 5: Formato da mensagem

`<tipo>(<escopo>): <descrição curta no imperativo, PT-BR>`

- **Tipos válidos**: `feat`, `fix`, `refactor`, `test`, `chore`, `migration`, `docs`, `spec`
- **Escopo**: nome do módulo/feature (ex: `processBilling`, `auth`, `plantOwnerOrder`)
- **Descrição**: imperativa ("adiciona", "remove", "corrige", "renomeia"), até ~72 caracteres, em PT-BR
- **Corpo (opcional)**: só inclua se o "porquê" não couber no título. Foque em **por que** foi feito, não no **o quê**
- **Voz**: escreva como se o próprio usuário tivesse escrito — nada de "I", "we", "Claude"

### Passo 6: Apresentar o plano

Mostre exatamente neste formato:

```
Plano de commits:
──────────────────────────────────────────
Commit 1: feat(processBilling): adiciona handler de cancelamento assíncrono
  📄 src/main/java/.../CancelProcessBillingHandler.java
  📄 src/main/java/.../ProcessBillingHandler.java

Commit 2: test(processBilling): cobre handler de cancelamento
  📄 src/test/java/.../CancelProcessBillingHandlerTest.java
──────────────────────────────────────────
Total: 2 commits
```

Se houver arquivos sensíveis detectados ou hooks pre-commit presentes, adicione antes do `Total:`:

```
⚠️  Arquivos sensíveis ignorados: .env.local
⚠️  Hooks pre-commit detectados — primeira execução pode demorar
```

Pergunte: **"Planejo criar [N] commit(s) com essas alterações. Podemos prosseguir?"**

Aguarde confirmação. Se o usuário pedir ajustes (mudar agrupamento, mensagem, ordem), aplique e reapresente o plano.

### Passo 7: Executar após confirmação

Para cada commit do plano:

1. `git add <arquivo1> <arquivo2> ...` (nunca `-A` ou `.`)
2. `git commit -m "<mensagem>"` usando HEREDOC se a mensagem tiver corpo:

```bash
git commit -m "$(cat <<'EOF'
feat(processBilling): adiciona handler de cancelamento assíncrono

Substitui o cancelamento síncrono em CancelSubscriptionUseCase para
evitar timeout em cancelamentos com muitas cobranças associadas.
EOF
)"
```

3. Se o hook pre-commit falhar:
   - **NÃO** use `--no-verify`
   - **NÃO** use `--amend` (o commit anterior não aconteceu; amend modificaria o commit *prévio*)
   - Investigue o erro, corrija, re-stage os arquivos afetados, e crie um **novo** `git commit`

Ao final, execute `git log --oneline -n <N>` e mostre o resultado.

## Examples

### Exemplo 1: Commit único, feature simples

User: "commita as alterações"

`git status` mostra:
```
M src/main/java/.../AuthService.java
M src/test/java/.../AuthServiceTest.java
```

Plano:
```
Commit 1: feat(auth): adiciona validação de token expirado em AuthService
  📄 src/main/java/.../AuthService.java
  📄 src/test/java/.../AuthServiceTest.java
```

Aqui código e teste vão juntos porque cobrem a mesma mudança na mesma camada.

### Exemplo 2: Múltiplos commits com migration + entidade + teste

User: "cria commit"

`git status` mostra:
```
A  src/main/resources/db/migration/2026/05/V20260519001__create_billing_queue.sql
A  src/main/java/.../BillingQueueEntity.java
A  src/main/java/.../BillingQueueService.java
A  src/test/java/.../BillingQueueServiceTest.java
M  application.properties
```

Plano:
```
Commit 1: chore(billingQueue): habilita feature flag billing.queue.enabled
  📄 application.properties

Commit 2: migration(billingQueue): cria tabela billing_queue
  📄 src/main/resources/db/migration/2026/05/V20260519001__create_billing_queue.sql

Commit 3: feat(billingQueue): adiciona entidade e service de fila de cobrança
  📄 src/main/java/.../BillingQueueEntity.java
  📄 src/main/java/.../BillingQueueService.java

Commit 4: test(billingQueue): cobre BillingQueueService
  📄 src/test/java/.../BillingQueueServiceTest.java
```

Ordem segue a hierarquia infra → migration → domínio → testes.

### Exemplo 3: Arquivo sensível detectado

User: "commita"

`git status` inclui `.env.local`.

O agente avisa **antes do plano**:

> ⚠️  Detectei `.env.local` nas alterações — arquivos `.env` normalmente não devem ser commitados (podem conter segredos). Quer mesmo incluir, ou excluo do plano?

Aguarda resposta e só então monta o plano.

## Troubleshooting

### Hook pre-commit falhou

Causa: lint, format, type check ou teste configurado no hook reprovou.

Solução: leia o output do hook, corrija os arquivos apontados, re-stage com `git add <arquivos>` e crie um **novo** `git commit` (não amend). Nunca use `--no-verify`.

### `git commit` reclama de "nothing to commit"

Causa: arquivos não foram staged corretamente, ou o hook removeu mudanças via auto-format.

Solução: rode `git status` para checar o estado real. Se o auto-format reverteu mudanças, re-stage explicitamente os arquivos formatados.

### Usuário pediu para amendar o último commit

Cause: amend modifica o commit anterior — pode reescrever histórico já enviado.

Solução: confirme com o usuário que ele quer mesmo amendar (não criar novo). Se sim, use `git commit --amend --no-edit` para manter a mensagem, ou `git commit --amend -m "<nova>"` para reescrever. Se o commit já foi pushado para uma branch compartilhada, **alerte** que será necessário force-push e peça confirmação extra.

### Mensagem do commit em inglês por hábito

Solução: o padrão Solarz é PT-BR. Reescreva no imperativo em PT-BR antes de apresentar o plano. Exemplo: `feat(auth): add token validation` → `feat(auth): adiciona validação de token`.
