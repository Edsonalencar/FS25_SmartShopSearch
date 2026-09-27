# FS25 Smart Shop Search — Requisitos de Software

**Versão:** 1.1  
**Projeto:** FS25 Mods Editor  
**Alvo:** Farming Simulator 25 / publicação no ModHub oficial  
**Status:** Requisitos para modelagem de implementação

---

## 1. Visão do produto

O **FS25 Smart Shop Search** será um mod completo para Farming Simulator 25 destinado a melhorar a descoberta de veículos, máquinas, implementos e demais itens da loja.

O produto deverá substituir a experiência limitada de pesquisa literal por um mecanismo capaz de compreender erros de digitação, variações linguísticas, múltiplos termos, atributos técnicos, números, unidades, comparadores e relações de compatibilidade.

Exemplo obrigatório:

```text
trtor
  ↓
trator
  ↓
tratores relevantes
```

Exemplo avançado:

```text
trtor jon dere entre 200 e 300 cv por menos de 150 mil
```

Interpretação esperada:

```text
categoria ≈ trator
marca ≈ John Deere
potência >= 200 cv
potência <= 300 cv
preço < 150000
```

O produto será desenvolvido desde o início visando qualidade de distribuição e submissão ao **ModHub oficial da GIANTS**.

---

## 2. Projeto open source de referência

Durante o levantamento inicial foi identificado o projeto open source **FS25_ShopSearch**, desenvolvido por **w33zl**:

- **Repositório:** https://github.com/w33zl/FS25_ShopSearch
- **Projeto:** `w33zl/FS25_ShopSearch`
- **Finalidade:** adicionar funcionalidade de pesquisa à loja do Farming Simulator 25.

O projeto deverá ser utilizado como **referência técnica para investigação e modelagem**, especialmente para compreender:

- integração com a interface da loja do FS25;
- pontos de extensão utilizados na GUI;
- acesso aos itens disponíveis na loja;
- interceptação/alteração da listagem;
- tratamento de input de pesquisa;
- atualização dos resultados exibidos;
- estrutura de arquivos de um mod de pesquisa funcional;
- práticas necessárias para funcionamento dentro do ambiente de scripting do FS25.

### 2.1 Relação com o FS25 Smart Shop Search

O `FS25_ShopSearch` **não será tratado automaticamente como dependência** do FS25 Smart Shop Search.

A arquitetura do nosso projeto deverá ser definida a partir dos requisitos deste documento e da API/pontos de extensão efetivamente disponíveis no Farming Simulator 25.

O projeto de referência deverá servir principalmente para:

```text
FS25_ShopSearch
      │
      │ estudo / engenharia reversa
      ▼
Pontos de extensão reais do FS25
      │
      ▼
Modelagem própria
      │
      ▼
FS25 Smart Shop Search
```

O Smart Shop Search possui escopo superior ao buscador de referência, incluindo:

- fuzzy search;
- tolerância a erros ortográficos;
- aliases e sinônimos;
- vocabulário FS25/agro;
- parser de números;
- parser de unidades;
- comparadores;
- intervalos;
- consultas compostas;
- filtros estruturados;
- ranking ponderado;
- compatibilidade entre equipamentos;
- explicabilidade dos resultados;
- localização;
- integração com ModHub quando oficialmente suportada.

### 2.2 Reutilização de código

Antes de copiar, modificar, incorporar ou redistribuir qualquer trecho de código do `FS25_ShopSearch`, deverá ser verificada a **licença vigente no repositório e os termos aplicáveis ao código específico**.

A existência de um repositório público/open source não deverá ser interpretada, por si só, como autorização irrestrita para reutilização.

Caso código seja efetivamente reutilizado:

1. a licença deverá permitir o uso pretendido;
2. as obrigações de atribuição deverão ser cumpridas;
3. arquivos ou trechos derivados deverão ser identificáveis;
4. a origem deverá ser documentada;
5. a reutilização deverá ser compatível com as regras de distribuição/publicação do ModHub.

Sempre que possível, o projeto deverá preferir **compreender o ponto de extensão e implementar sua própria arquitetura**, evitando acoplamento desnecessário ao mod de referência.

### 2.3 Uso durante a modelagem

A etapa de modelagem deverá analisar especificamente no `FS25_ShopSearch`:

- bootstrap/registro do mod;
- integração com a Shop GUI;
- hooks utilizados;
- mecanismo atual de busca;
- obtenção dos `StoreItem`;
- campos pesquisados;
- atualização visual dos resultados;
- tratamento de teclado/input;
- possíveis conflitos com outros mods;
- limitações arquiteturais que não deverão ser reproduzidas.

As conclusões dessa análise deverão ser confrontadas com a documentação oficial da GIANTS antes de serem adotadas.

---

## 3. Princípios do produto

1. Não haverá uma versão reduzida tratada como MVP.
2. Os requisitos deste documento compõem o produto planejado.
3. A busca deverá funcionar localmente e não depender de serviços externos para suas funções essenciais.
4. Erros de digitação não devem impedir que o usuário encontre o que procura.
5. A relevância dos resultados deverá ser calculada, e não determinada apenas por correspondência literal.
6. A solução deverá preservar o funcionamento normal da loja caso o mod encontre uma falha.
7. A arquitetura deverá priorizar compatibilidade com outros mods.
8. A implementação deverá seguir as exigências técnicas aplicáveis à publicação no ModHub.
9. Funcionalidades dependentes de APIs não expostas pelo FS25 serão implementadas somente quando houver um ponto de extensão tecnicamente suportado.

---

## 4. Escopo funcional

O produto deverá incluir:

- integração de pesquisa à experiência da loja;
- indexação do catálogo;
- pesquisa por nome;
- pesquisa por marca;
- pesquisa por categoria;
- pesquisa por nome do mod;
- pesquisa por autor;
- fuzzy search;
- normalização textual;
- tokenização;
- aliases;
- sinônimos;
- vocabulário específico de FS25/agro;
- consultas com múltiplos termos;
- ranking de relevância;
- filtros estruturados;
- parser de números;
- parser de unidades;
- interpretação de comparadores;
- interpretação de intervalos;
- consultas compostas em linguagem natural;
- busca por características técnicas disponíveis;
- busca por compatibilidade entre veículos e implementos;
- explicabilidade dos resultados;
- internacionalização/localização;
- logging e diagnóstico;
- fallback seguro;
- validação compatível com o processo de publicação no ModHub;
- investigação da integração com o catálogo/tela do ModHub online e implementação quando tecnicamente suportada.

---

# 5. Requisitos funcionais

## 4.1 Interface e operação

### RF-001 — Acesso à busca

O jogador deve conseguir acessar a pesquisa diretamente durante a utilização da loja.

### RF-002 — Atalho configurável

Quando tecnicamente adequado à integração com a GUI, o sistema deverá permitir abrir/focar a pesquisa por um input configurável pelo sistema de controles do FS25.

### RF-003 — Atualização dos resultados

Alterações na consulta ou nos filtros deverão atualizar os resultados sem exigir reinicialização da loja ou do jogo.

### RF-004 — Limpar pesquisa

O jogador deverá conseguir remover consulta e filtros rapidamente e retornar à listagem normal.

### RF-005 — Estado vazio

Uma consulta sem resultados deverá apresentar estado apropriado e nunca gerar erro ou travamento.

---

## 4.2 Campos pesquisáveis

### RF-006 — Nome

O sistema deverá localizar itens pelo nome/título.

### RF-007 — Marca

O sistema deverá localizar itens pela marca.

### RF-008 — Categoria

O sistema deverá pesquisar categorias de equipamentos.

### RF-009 — Mod de origem

Itens adicionados por mods deverão poder ser pesquisados pelo nome do mod quando essa informação estiver disponível.

### RF-010 — Autor

O sistema deverá permitir pesquisa pelo autor do mod quando o metadado estiver disponível.

### RF-011 — Especificações

Características técnicas confiavelmente disponibilizadas pelo catálogo/API do jogo deverão poder participar da pesquisa e/ou filtragem.

---

# 6. Normalização linguística

### RF-012 — Case insensitive

A busca não deverá diferenciar letras maiúsculas de minúsculas.

```text
JOHN DEERE
John Deere
john deere
```

devem ser semanticamente equivalentes para pesquisa.

### RF-013 — Normalização de acentos

Variações de acentuação deverão ser tratadas de forma equivalente quando aplicável.

### RF-014 — Espaçamento

Espaços duplicados ou desnecessários não deverão alterar o significado da consulta.

### RF-015 — Tokenização

O mecanismo deverá decompor consultas compostas em unidades pesquisáveis.

```text
trtor jon dere 200 cv
```

poderá gerar conceitualmente:

```text
trtor
jon
dere
200
cv
```

---

# 7. Fuzzy Search

### RF-016 — Erros de remoção

```text
trtor → trator
```

### RF-017 — Erros de inserção

Caracteres extras não deverão necessariamente impedir uma correspondência relevante.

### RF-018 — Substituição de caracteres

Erros de tecla deverão ser tolerados quando houver similaridade suficiente.

### RF-019 — Transposição

```text
tratro → trator
```

deverá ser reconhecido como correspondência provável.

### RF-020 — Erros em marcas

Exemplos:

```text
jon dere
jhon deere
john dere
```

devem ser capazes de recuperar **John Deere**.

### RF-021 — Limiar de similaridade

O fuzzy matching deverá possuir limiar mínimo para impedir correspondências sem relação útil.

### RF-022 — Termos curtos

O algoritmo deverá aplicar regras específicas a palavras curtas para evitar falsos positivos excessivos.

---

# 8. Vocabulário, aliases e sinônimos

### RF-023 — Dicionário extensível

O mecanismo deverá possuir uma camada de aliases/sinônimos independente do núcleo de busca.

Exemplo conceitual:

```yaml
tractor:
  - trator
  - tratores
  - tractor

trailer:
  - reboque
  - carreta
  - trailer

seeder:
  - semeadeira
  - plantadeira
```

### RF-024 — Vocabulário FS25/agro

Termos comuns utilizados pelos jogadores poderão ser relacionados aos conceitos utilizados internamente pelo jogo.

### RF-025 — Vocabulário localizado

Aliases deverão poder variar por idioma sem exigir alterações no algoritmo de pesquisa.

---

# 9. Números e unidades

### RF-026 — Parser numérico

O sistema deverá identificar valores numéricos dentro da consulta.

### RF-027 — Potência

Unidades de potência suportadas pelo domínio deverão ser interpretadas.

Exemplo:

```text
200 cv
200cv
200 hp
```

### RF-028 — Capacidade

Quando a informação existir no item:

```text
40000 l
40.000 litros
40 mil litros
```

deverão poder ser transformados em critérios comparáveis.

### RF-029 — Valores monetários

Expressões monetárias deverão ser normalizadas quando usadas em critérios de preço.

```text
150000
150.000
150 mil
R$ 150 mil
```

### RF-030 — Conversão de unidades

Quando unidades equivalentes forem suportadas, a camada de interpretação deverá normalizá-las antes da comparação.

---

# 10. Comparadores e intervalos

### RF-031 — Maior que

```text
acima de 200 cv
mais de 200 cv
```

### RF-032 — Menor que

```text
menos de 150 mil
abaixo de 150000
```

### RF-033 — Intervalos

```text
entre 200 e 300 cv
```

deverá produzir limites inferior e superior.

### RF-034 — Combinação de restrições

O sistema deverá combinar múltiplos critérios.

Exemplo:

```text
trator john deere entre 200 e 300 cv por menos de 150 mil
```

---

# 11. Consultas compostas

### RF-035 — Múltiplos conceitos

Uma única consulta poderá conter simultaneamente:

- categoria;
- marca;
- especificações;
- unidades;
- preço;
- termos aproximados.

### RF-036 — Consulta parcialmente compreendida

Se apenas parte da consulta puder ser interpretada estruturalmente, os termos restantes deverão continuar participando da busca textual.

O mecanismo não deverá descartar toda a consulta por falha parcial do parser.

---

# 12. Ranking de relevância

### RF-037 — Score

Cada resultado deverá possuir um score calculado.

### RF-038 — Correspondência exata

Correspondências exatas relevantes deverão possuir peso superior às aproximadas equivalentes.

### RF-039 — Correspondência fuzzy

A pontuação deverá considerar a distância/similaridade entre consulta e termo indexado.

### RF-040 — Peso por campo

Campos diferentes poderão possuir pesos distintos.

Exemplo inicial conceitual:

```text
nome       → peso alto
categoria  → peso alto
marca      → peso alto
spec       → peso médio/alto
mod        → peso médio
autor      → peso secundário
```

Os valores concretos serão definidos e calibrados na modelagem/testes.

### RF-041 — Cobertura da consulta

Itens que satisfaçam uma proporção maior dos conceitos pesquisados deverão receber vantagem no ranking.

### RF-042 — Penalização

Correspondências fracas ou excessivamente aproximadas deverão receber penalização.

---

# 13. Filtros estruturados

### RF-043 — Categoria

O jogador deverá poder restringir resultados por categoria quando disponível.

### RF-044 — Marca

Deverá ser possível filtrar por marca.

### RF-045 — Preço

Deverá ser possível restringir por faixa de preço.

### RF-046 — Especificações

Atributos técnicos deverão virar filtros quando forem expostos de forma consistente pelo FS25.

### RF-047 — Origem

Quando tecnicamente possível, deverá ser possível distinguir conteúdo base, DLC e mods.

---

# 14. Compatibilidade entre equipamentos

### RF-048 — Relações conhecidas

Quando o FS25 disponibilizar metadados suficientes, o sistema deverá considerar relações conhecidas entre veículos e implementos.

### RF-049 — Busca contextual

O mecanismo deverá permitir evolução para consultas como:

```text
implementos compatíveis com este trator
```

ou equivalentes de interface.

### RF-050 — Não inferir compatibilidade sem evidência

O sistema não deverá afirmar compatibilidade apenas por similaridade textual.

Uma relação deverá estar apoiada em dados técnicos acessíveis no jogo.

---

# 15. Explicabilidade

### RF-051 — Motivo do resultado

O mecanismo deverá ser capaz de representar internamente por que um item recebeu determinada relevância.

Exemplo:

```text
John Deere 6R

✓ categoria: trator
✓ marca: John Deere
✓ potência dentro de 200–300 cv
✓ preço dentro do limite
```

### RF-052 — Exibição opcional

A GUI poderá apresentar essas informações de forma discreta quando isso melhorar a experiência sem poluir a interface.

---

# 16. Catálogo de mods / ModHub

### RF-053 — Investigação de integração

A modelagem deverá identificar quais APIs e pontos de extensão relacionados ao catálogo/tela de mods são oficialmente acessíveis aos scripts do FS25.

### RF-054 — Integração quando suportada

Caso exista acesso suportado ao catálogo do ModHub, o mesmo motor de busca deverá ser reutilizável para melhorar sua descoberta.

### RF-055 — Isolamento

A integração com ModHub deverá constituir um adaptador/subsistema separado do mecanismo de busca da loja.

### RF-056 — Ausência de API

Caso o catálogo remoto não seja exposto de forma suportada, o mod não deverá utilizar hacks, scraping externo ou alterações inseguras para contornar a limitação.

Essa limitação deverá ser documentada.

---

# 17. Internacionalização

### RF-057 — PT-BR

Português brasileiro será um idioma prioritário do produto.

### RF-058 — Estrutura multilíngue

Strings de interface e vocabulários não deverão ficar rigidamente acoplados ao código.

### RF-059 — Vocabulários por idioma

Sinônimos e aliases deverão poder possuir arquivos/conjuntos específicos por localização.

---

# 18. Resiliência

### RF-060 — Fallback seguro

Falhas no mecanismo de pesquisa não deverão impedir o funcionamento da loja original.

### RF-061 — Dados ausentes

Itens sem determinado metadado deverão continuar indexáveis pelos campos disponíveis.

### RF-062 — Mods malformados

Dados inesperados provenientes de outros mods não deverão provocar falha global do buscador.

---

# 19. Requisitos não funcionais

### RNF-001 — Desempenho

Pesquisa, filtragem e ranking não deverão provocar travamentos perceptíveis da interface.

### RNF-002 — Latência

Após a construção do índice, pesquisas comuns deverão apresentar resposta percebida como imediata.

Metas numéricas serão definidas durante os testes de desempenho.

### RNF-003 — Memória

O índice deverá evitar duplicação desnecessária de grandes estruturas dos `StoreItem`.

### RNF-004 — Offline-first

As funcionalidades essenciais deverão funcionar sem conexão à internet.

### RNF-005 — Modularidade

O mecanismo deverá possuir responsabilidades separadas para:

```text
normalização
tokenização
parsing
fuzzy matching
aliases
indexação
scoring
filtros
compatibilidade
renderização
```

### RNF-006 — Extensibilidade

Novos campos, unidades, idiomas, filtros e regras deverão poder ser adicionados sem reescrever o núcleo.

### RNF-007 — Compatibilidade

A implementação deverá minimizar monkey-patching/sobrescritas destrutivas da GUI e de funções nativas.

### RNF-008 — Observabilidade

Eventos relevantes e erros deverão ser registrados adequadamente no `log.txt`.

### RNF-009 — Logging controlado

O mod não deverá produzir spam de log durante funcionamento normal.

### RNF-010 — Segurança de estado

Ativar, desativar ou remover o mod não deverá modificar permanentemente arquivos do jogo base.

---

# 20. Requisitos para publicação no ModHub

O desenvolvimento deverá ser conduzido considerando desde o início o processo de QA da GIANTS.

### RMH-001 — Estrutura válida

O mod deverá possuir estrutura e `modDesc.xml` válidos para a versão de FS25 suportada no momento da submissão.

### RMH-002 — Metadados

Nome, descrição, ícone e demais metadados obrigatórios deverão estar preparados para submissão.

### RMH-003 — Empacotamento

A distribuição deverá ser realizada no formato esperado pelo Farming Simulator/ModHub, sem arquivos de desenvolvimento desnecessários.

### RMH-004 — TestRunner

Antes de cada release candidata ao ModHub, o pacote deverá ser validado com a versão atual do **Farming Simulator 25 TestRunner**.

### RMH-005 — Log limpo

O mod deverá ser testado visando ausência de erros gerados por ele no log durante os fluxos suportados.

### RMH-006 — Autoteste

Antes da submissão, deverão ser executados testes funcionais no jogo.

### RMH-007 — Estabilidade

O mod não deverá introduzir crashes ou instabilidade conhecida.

### RMH-008 — Performance

O índice e o ranking não deverão introduzir impacto excessivo de desempenho.

### RMH-009 — Compatibilidade

Deverão ser realizados testes com catálogo base e uma seleção representativa de mods.

### RMH-010 — Dependências

O produto deverá evitar dependências externas obrigatórias e deverá respeitar as exigências atuais do ModHub no momento da submissão.

### RMH-011 — Conformidade atual

As regras e ferramentas da GIANTS podem evoluir. A release deverá ser validada contra a documentação, TestRunner e requisitos do ModHub vigentes na data da submissão.

---

# 21. Critérios de aceitação

## Busca textual

- [ ] `trator` encontra tratores relevantes.
- [ ] `TRATOR` produz comportamento equivalente.
- [ ] acentuação não quebra correspondências equivalentes.
- [ ] espaços redundantes não alteram o resultado.

## Fuzzy search

- [ ] `trtor` encontra `trator`.
- [ ] `tratro` encontra `trator`.
- [ ] `jon dere` encontra `John Deere`.
- [ ] `jhon deere` encontra `John Deere`.
- [ ] `pulverizdor` encontra `pulverizador`.
- [ ] termos não relacionados não aparecem com relevância alta apenas por coincidência de caracteres.

## Consultas compostas

- [ ] múltiplos termos influenciam o ranking.
- [ ] partes não interpretadas estruturalmente continuam pesquisáveis.
- [ ] consultas combinando categoria e marca funcionam.

## Números

- [ ] números inteiros são identificados.
- [ ] `150 mil` pode ser normalizado.
- [ ] formatos numéricos localizados suportados são interpretados corretamente.

## Unidades

- [ ] potência é identificável quando o atributo existe.
- [ ] capacidade é identificável quando o atributo existe.
- [ ] unidades equivalentes suportadas podem ser normalizadas.

## Comparadores

- [ ] `acima de X` produz limite inferior.
- [ ] `abaixo de X` produz limite superior.
- [ ] `entre X e Y` produz intervalo.

## Ranking

- [ ] correspondência exata supera fuzzy equivalente.
- [ ] cobertura maior da consulta aumenta relevância.
- [ ] matches fracos recebem penalização.
- [ ] nome/categoria/marca recebem pesos adequados.

## Mods

- [ ] itens adicionados por mods são indexados quando registrados no catálogo.
- [ ] nome do mod participa da pesquisa quando disponível.
- [ ] autor participa da pesquisa quando disponível.

## Resiliência

- [ ] consulta sem resultado não gera erro.
- [ ] metadado ausente não quebra indexação.
- [ ] falha interna não inutiliza a loja.
- [ ] remoção do mod restaura naturalmente o comportamento original.

## Publicação

- [ ] pacote final passa no TestRunner aplicável.
- [ ] não há erros atribuíveis ao mod no `log.txt` nos cenários suportados.
- [ ] estrutura do ZIP está correta.
- [ ] metadados de publicação estão completos.
- [ ] testes funcionais foram executados antes da submissão.

---

# 22. Fluxo funcional

```text
Consulta do usuário
        │
        ▼
TextNormalizer
        │
        ▼
Tokenizer
        │
        ├──────────────► AliasResolver
        │
        ▼
QueryParser
        │
        ├── números
        ├── unidades
        ├── comparadores
        └── intervalos
        │
        ▼
SearchEngine
        │
        ├── ExactMatcher
        ├── FuzzyMatcher
        ├── FieldMatcher
        └── CompatibilityResolver
        │
        ▼
SearchScorer
        │
        ▼
StructuredFilters
        │
        ▼
Ranking
        │
        ▼
SearchResult[]
        │
        ├── item
        ├── score
        └── matchReasons[]
        │
        ▼
GUI
```

---

# 23. Componentes esperados para a modelagem

A modelagem de implementação deverá avaliar uma arquitetura equivalente a:

```text
SmartShopSearch
│
├── Bootstrap
│
├── ShopIntegration
│
├── SearchIndex
│
├── TextNormalizer
│
├── Tokenizer
│
├── AliasResolver
│
├── QueryParser
│   ├── NumberParser
│   ├── UnitParser
│   └── ComparatorParser
│
├── SearchEngine
│   ├── ExactMatcher
│   ├── FuzzyMatcher
│   └── FieldMatcher
│
├── SearchScorer
├── FilterEngine
├── CompatibilityResolver
├── SearchResult
├── Localization
├── Diagnostics
│
├── GUI
│
└── ModHubAdapter
    └── somente se houver API/ponto de extensão suportado
```

Esta estrutura é uma **direção para modelagem**, não uma imposição arquitetural. A arquitetura final deverá ser decidida após investigação dos pontos de extensão reais do FS25.

---

# 24. Questões obrigatórias para a modelagem

Antes de iniciar a implementação definitiva, deverão ser respondidas:

1. Qual é o ponto de extensão mais seguro da GUI da loja?
2. Quais campos do `StoreItem` são confiáveis em jogo base, DLC e mods?
3. Quais specs podem ser indexadas genericamente?
4. Como extrair potência, capacidade e demais atributos sem acoplamento excessivo?
5. Qual algoritmo fuzzy será utilizado?
6. Qual limiar será utilizado por tamanho de token?
7. Como será calculado o score?
8. Quando o índice será construído?
9. Como ele será invalidado/reconstruído?
10. Como aliases serão localizados?
11. Como consultas estruturadas serão representadas internamente?
12. Como compatibilidade será determinada sem inferências falsas?
13. Quais hooks da GUI minimizam conflitos?
14. A tela do ModHub é acessível por scripts de mods?
15. Quais funcionalidades são permitidas pela política atual do ModHub?
16. Como automatizar os testes de regressão do mecanismo de busca?
17. Como executar TestRunner e validações de release de forma repetível?
18. Quais pontos de extensão utilizados por `w33zl/FS25_ShopSearch` continuam adequados para a versão atual do FS25?
19. Quais decisões do projeto de referência podem ser reaproveitadas conceitualmente e quais devem ser substituídas pela nossa arquitetura?
20. Qual é a licença vigente do `FS25_ShopSearch` no momento da implementação e quais obrigações ela impõe caso haja reutilização de código?

---

# 25. Definição de pronto

O **FS25 Smart Shop Search 1.0** estará pronto para submissão quando:

1. os requisitos aplicáveis deste documento estiverem implementados;
2. os critérios de aceitação estiverem satisfeitos;
3. as funcionalidades dependentes de API tiverem sido implementadas ou formalmente classificadas como indisponíveis por limitação comprovada do FS25;
4. testes funcionais tiverem sido executados;
5. testes de regressão do mecanismo de busca estiverem aprovados;
6. o desempenho estiver dentro das metas definidas na modelagem;
7. não houver erros atribuíveis ao mod nos fluxos suportados;
8. o pacote estiver corretamente preparado;
9. o TestRunner aplicável for aprovado;
10. os requisitos vigentes do ModHub tiverem sido revisados antes da submissão.

---

# 26. Próxima etapa

Este documento é a entrada para a **Modelagem Técnica de Implementação**.

A próxima etapa deverá produzir:

- arquitetura de componentes;
- fluxo de inicialização;
- integração com a API do FS25;
- integração com a GUI;
- modelo do índice;
- modelo da consulta;
- modelo do resultado;
- algoritmo fuzzy;
- algoritmo de scoring;
- parser de linguagem;
- estratégia de compatibilidade;
- estratégia de localização;
- estratégia de testes;
- pipeline de validação/TestRunner;
- estrutura final de arquivos do mod;
- mapeamento `RF/RNF/RMH → componente → teste`.
