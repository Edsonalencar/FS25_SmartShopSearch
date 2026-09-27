# ADR-0005: Fuzzy em dois estágios (trigramas + OSA restrito)

## Status
Aceito

## Contexto
Tolerância a erros de digitação (RF-016..022) precisa cobrir remoção,
inserção, substituição e transposição, sem custo O(n) por consulta contra
todo o vocabulário. Busca fonética (Soundex/Metaphone) é dependente de
idioma e está fora do escopo (ver "O que não estamos fazendo").

## Decisão
Estágio (a): geração de candidatos por trigramas do vocabulário do índice.
Estágio (b): verificação com distância de Damerau-Levenshtein restrita (OSA),
com limite de distância e *early exit*. Limiar de distância por tamanho do
token (`Weights.fuzzyMaxByLen`).

## Consequências
- Cobre as quatro operações de edição com custo controlado (candidatos
  filtrados por trigrama antes do cálculo de distância).
- Termos muito curtos (≤3 bytes) usam só exato/prefixo — evita falsos
  positivos (RF-022).
- Base para o fuzzy de frase (ADR-0014), que estende o mesmo mecanismo a
  janelas de 2–3 tokens.
