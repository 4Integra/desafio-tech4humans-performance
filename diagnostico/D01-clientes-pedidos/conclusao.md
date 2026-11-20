# Diagnóstico D01 — `GET /clientes/:id/pedidos`

## Problema medido

D01 representa 20% da carga. Nas três linhas de base, recebeu 28, 33 e 32
requisições, com medianas de `28827.875152`, `25091.770438` e `26027.9899075 ms`.
A mediana das três medianas é `26027.9899075 ms`; não houve erro classificado para
a rota. O comportamento é recorrente, embora os percentis altos tenham amostra
pequena.

## Evidências

### Medido

- Há 100 mil clientes, 500 mil pedidos e 1,5 milhão de itens.
- Todo cliente tem 5 pedidos; cada pedido tem de 1 a 5 itens, mediana 3.
- A consulta por `cliente_id` fez `Parallel Seq Scan` em 500 mil pedidos, removeu
  499995 linhas e levou `207.234`, `183.969` e `113.931 ms` isoladamente.
- A consulta por `pedido_id` fez `Parallel Seq Scan` em 1,5 milhão de itens,
  removeu 1499997 linhas e levou `203.266`, `187.488` e `116.347 ms` isoladamente.
- Durante a carga mista, a CPU média do banco foi `81.8028%`, `95.8186%` e
  `95.6324%`, próxima do limite de 1 CPU nas duas últimas execuções.

### Observado no código

- A rota executa consultas aninhadas e sequenciais: uma consulta de itens para
  cada pedido e uma consulta de produto para cada item.
- No caso mediano são 22 consultas sequenciais por requisição; cada uma abre e
  fecha uma conexão PostgreSQL independente.
- Existem apenas índices de chave primária. Os filtros `pedidos.cliente_id` e
  `itens_pedido.pedido_id` não têm índice.

### Interpretação

O volume lido é desproporcional ao resultado: uma requisição mediana devolve 5
pedidos e 15 itens, mas executa uma varredura dos 500 mil pedidos e cinco
varreduras dos 1,5 milhão de itens. Sob concorrência, esse trabalho repetido é
compatível com a pressão observada no PostgreSQL. As conexões abertas por consulta
e a serialização sequencial podem acrescentar custo, mas seu impacto não foi
medido separadamente.

## Hipótese causal

Nas condições da linha de base, a causa provável da latência elevada de D01 é a
combinação de consultas N+1 sequenciais com varreduras completas repetidas de
`pedidos` e `itens_pedido` ao filtrar pelas chaves estrangeiras sem índices. Com
20 VUs e D01 em 20% da carga, essas varreduras concorrem pela CPU limitada do
PostgreSQL e ampliam o tempo de resposta.

Esta é uma hipótese específica e testável, não uma causalidade definitivamente
demonstrada. Ela seria enfraquecida se uma medição controlada mostrasse que a
quantidade de varreduras e linhas examinadas não acompanha a latência de D01, ou
se outro estágio respondesse pela maior parte do tempo sob as mesmas condições.

## Limitações

- `EXPLAIN ANALYZE` foi executado isoladamente, com estado de cache não controlado;
  seus tempos não decompõem os 25–29 segundos observados no HTTP.
- CPU e memória pertencem à carga mista, não exclusivamente a D01.
- Não houve tracing fim a fim; custo de conexão, fila, logging e serialização não
  foi medido separadamente.
- A linha de base contém somente 28–33 requisições D01 por execução.

## Reprodução

Executar no diretório do projeto, com os containers originais ativos:

```bash
docker compose exec -T banco psql -U loja -d loja < diagnostico/D01-clientes-pedidos/comandos.sql
```

CPU bruta por container, para cada `recursos.csv`:

```bash
awk -F, 'NR>1 && $2 ~ /banco/ {v=$3+0; n++; s+=v; if(n==1||v<min) min=v; if(n==1||v>max) max=v} END {print n, s/n, min, max}' resultados/<execucao>/recursos.csv
awk -F, 'NR>1 && $2 ~ /api/ {v=$3+0; n++; s+=v; if(n==1||v<min) min=v; if(n==1||v>max) max=v} END {print n, s/n, min, max}' resultados/<execucao>/recursos.csv
```

As saídas relevantes estão em `evidencias.txt`.
