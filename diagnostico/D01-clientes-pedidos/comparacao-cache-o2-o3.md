# Comparação controlada de cache — O2 × O3

## Pergunta e escopo

Pergunta: a presença do índice `idx_itens_pedido_pedido_id` aumentou leituras ou substituições de buffers durante a carga mista, contribuindo para a regressão oficial observada na O3?

Esta é uma investigação diagnóstica, separada dos benchmarks oficiais anteriores. Nenhuma implementação, configuração persistente, ferramenta oficial ou resultado anterior foi alterado.

## Procedimento reproduzível

As configurações foram materializadas em worktrees temporárias e destacadas, sem alterar a branch `main`:

- O2: commit `bd9742c70332cc4eb49e88a8cbb408d73a404ded`, batching de itens e produtos, sem o índice.
- O3: commit `6eaacb753556eecb7927e1fdc0268938b3b56d70`, mesma API acrescida de `banco/03-indice-itens-pedido-pedido-id.sql`.

O diff O2→O3 contém a hipótese documental em `experimentos.md` e, como única diferença funcional, o arquivo SQL do índice. A ordem foi alternada: O2-1, O3-1, O2-2, O3-2, O2-3, O3-3.

Para cada rodada:

1. `docker compose down -v` e `docker compose up -d --build` recriaram o banco com os SQLs da versão correspondente.
2. Foram conferidos commit, árvore limpa fora de `resultados/`, presença/ausência do índice, cardinalidades e limites.
3. O verificador oficial confirmou as 42 respostas antes da medição.
4. Foi capturado um snapshot anterior.
5. O `scripts/medir.sh` original foi executado com 20 VUs, 60s, aquecimento de 15s e semente 42.
6. Após dois segundos para publicação das estatísticas acumuladas, foi capturado o snapshot posterior.
7. Foram conferidos `contexto.txt`, arquivos obrigatórios e o contrato registrado pelo próprio `medir.sh`.

Cada recriação produziu as mesmas cardinalidades `100000|500000|1500000|20000`. Os limites permaneceram API 0,5 CPU/256 MiB e PostgreSQL 1 CPU/512 MiB. `shared_buffers=128MB` e `track_io_timing=off`. O índice estava ausente em O2 e presente em O3. Todos os seis `contexto.txt` registram zero arquivos alterados sem commit.

Houve uma tentativa abortada antes de qualquer snapshot ou medição porque a API ainda não estava pronta. O procedimento passou a aguardar a saúde da API com tentativas limitadas; O2-1 foi então reiniciada desde a recriação do banco. A tentativa abortada não integra os dados.

## Instrumentos e arquivos

- Consulta dos snapshots: `comparacao-cache-snapshot.sql`.
- Orquestração das rodadas: `comparacao-cache-rodada.sh`.
- Snapshots e logs brutos: `comparacao-cache-o2-o3/<execução>/`.
- Cálculo determinístico dos deltas e medianas: `comparacao-cache-analisar.js`.
- Saída integral dos cálculos: `comparacao-cache-calculos.json`.

Reprodução dos cálculos, sem alterar as fontes:

```bash
docker run --rm \
  -v /home/kakau/meu-desafio:/workspace:ro \
  node:20.18.0-alpine \
  node /workspace/diagnostico/D01-clientes-pedidos/comparacao-cache-analisar.js /workspace
```

Os deltas são `depois - antes`. Para `pg_stat_io`, foram somados `client backend` e `background worker` para relações, mantendo `normal` e `bulkread` separados. A normalização divide o delta pelo total de requisições concluídas registrado em `resumo.txt`. A mediana é calculada sobre as três execuções de cada configuração.

O analisador falha se o servidor reiniciar ou se `pg_stat_io.stats_reset` mudar no intervalo. Não ocorreu nenhum desses eventos.

## Evidências por execução

### Desempenho produzido pelo medir.sh

| Execução | Requisições | req/s | p95 geral (ms) | p95 D01 (ms) | Erros |
| --- | ---: | ---: | ---: | ---: | ---: |
| O2-1 | 109 | 1.50 | 33979.6 | 32014.4 | 0.00% |
| O2-2 | 112 | 1.52 | 36110.1 | 35607.8 | 0.00% |
| O2-3 | 132 | 1.80 | 31148.3 | 28961.4 | 0.76% |
| O3-1 | 164 | 2.31 | 28249.7 | 15331.2 | 0.61% |
| O3-2 | 162 | 2.33 | 28001.8 | 14529.4 | 0.62% |
| O3-3 | 154 | 2.23 | 29928.1 | 16237.5 | 0.00% |

Os erros foram um timeout de `top-produtos` em O2-3 e O3-1 e um timeout de `vendas-por-dia` em O3-2. D01 não apresentou erros.

### Deltas de pg_stat_io

Valores combinam `client backend` e `background worker` apenas para `object=relation`.

| Execução | normal reads | normal hits | normal evictions | bulkread reads | bulkread hits | bulkread evictions | bulkread reuses |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| O2-1 | 122 | 157414 | 0 | 1773112 | 723812 | 0 | 1762306 |
| O2-2 | 117 | 154200 | 0 | 1717737 | 740967 | 0 | 1707031 |
| O2-3 | 134 | 171424 | 0 | 1892144 | 840061 | 486 | 1880640 |
| O3-1 | 9163 | 448837 | 5772 | 1820556 | 839300 | 3975 | 1810855 |
| O3-2 | 8319 | 414479 | 5058 | 1766135 | 819940 | 3642 | 1756629 |
| O3-3 | 8374 | 421473 | 5197 | 1786851 | 759280 | 3344 | 1777553 |

### Relações e índice

| Execução | pedidos heap read | itens heap read | índice read | índice hit | índice scans |
| --- | ---: | ---: | ---: | ---: | ---: |
| O2-1 | 1464007 | 331491 | 0 | 0 | 0 |
| O2-2 | 1424305 | 316000 | 0 | 0 | 0 |
| O2-3 | 1565325 | 349336 | 0 | 0 | 0 |
| O3-1 | 1789702 | 59459 | 2301 | 192463 | 64895 |
| O3-2 | 1730521 | 63237 | 2204 | 166688 | 56270 |
| O3-3 | 1761493 | 52643 | 2056 | 179749 | 60576 |

O índice foi efetivamente utilizado nas três rodadas O3. Em paralelo, as leituras do heap de `itens_pedido` foram muito menores. As leituras de `pedidos` permaneceram elevadas, compatíveis com a varredura completa já preservada no diagnóstico pós-índice.

## Medianas das três execuções

### Desempenho e recursos

CPU e memória são as medianas das médias calculadas sobre todas as amostras de `recursos.csv` de cada execução.

| Indicador | O2 | O3 | Variação O2→O3 |
| --- | ---: | ---: | ---: |
| Requisições | 112 | 162 | 44.64285714285714% |
| Requisições/s | 1.52 | 2.31 | 51.97368421052633% |
| p95 geral (ms) | 33979.6 | 28249.7 | -16.86276471765411% |
| p95 D01 (ms) | 32014.4 | 15331.2 | -52.11154980258883% |
| CPU média API (%) | 8.79394736842105 | 11.81142857142857 | 34.31315968348021% |
| Memória média API (MiB) | 28.818108108108106 | 36.23694444444445 | 25.743661965960275% |
| CPU média PostgreSQL (%) | 97.81157894736842 | 96.5011111111111 | -1.3397880397805095% |
| Memória média PostgreSQL (MiB) | 394.2972972972973 | 387.84722222222223 | -1.635840549576928% |

Nesta comparação diagnóstica, O3 apresentou maior vazão e menores p95 geral e D01, com maior CPU e memória da API. A CPU do PostgreSQL permaneceu próxima do limite nas duas configurações.

### Cache e I/O

| Indicador | O2 | O3 | Variação O2→O3 |
| --- | ---: | ---: | ---: |
| normal reads | 122 | 8374 | 6763.934426229508% |
| normal hits | 157414 | 421473 | 167.74810372647923% |
| normal evictions | 0 | 5197 | não definida (base zero) |
| taxa de hit normal (razão) | 0.9992255738370912 | 0.9803239371993245 | -1.8916285904476138% |
| bulkread reads | 1773112 | 1786851 | 0.7748523499925497% |
| bulkread hits | 740967 | 819940 | 10.65809948351275% |
| bulkread evictions | 0 | 3642 | não definida (base zero) |
| bulkread reuses | 1762306 | 1777553 | 0.865173244601114% |
| normal reads por requisição | 1.0446428571428572 | 54.37662337662338 | 5105.283605283605% |
| normal hits por requisição | 1376.7857142857142 | 2736.810975609756 | 98.78263895479422% |
| normal evictions por requisição | 0 | 33.746753246753244 | não definida (base zero) |
| bulkread reads por requisição | 15336.9375 | 11100.951219512195 | -27.61950539661393% |
| bulkread reuses por requisição | 15241.348214285714 | 11041.798780487805 | -27.553661098443193% |
| pedidos heap read | 1464007 | 1761493 | 20.319984808815803% |
| itens_pedido heap read | 331491 | 59459 | -82.06316310246734% |
| índice read | 0 | 2204 | não definida (base zero) |
| índice hit | 0 | 179749 | não definida (base zero) |
| índice scans | 0 | 60576 | não definida (base zero) |

Distribuição agregada das rotas nas três execuções:

| Rota | O2 | O3 |
| --- | ---: | ---: |
| cliente | 94 | 125 |
| cliente-por-email | 66 | 89 |
| pedidos-do-cliente | 74 | 94 |
| pedidos-por-status | 46 | 58 |
| busca-produtos | 47 | 77 |
| vendas-por-dia | 23 | 33 |
| top-produtos | 3 | 4 |

## Interpretação

### Evidências observadas

1. O3 apresentou, em todas as repetições, mais leituras e substituições no contexto `normal`, inclusive após normalização pelo volume concluído. A taxa de hit `normal` foi menor.
2. O índice teve leituras, hits e scans nas três rodadas O3. A elevação de hits `normal` é compatível com o acesso adicional ao índice, mas `pg_stat_io` não atribui os demais deltas a uma relação ou rota.
3. A mediana de leituras do heap de `itens_pedido` caiu de 331491 para 59459. Isso confirma a mudança do padrão de acesso local já observada com `EXPLAIN`.
4. As leituras `bulkread` absolutas ficaram próximas, mas caíram por requisição concluída. `reuses` também caiu por requisição. `reuses` não foi tratado como equivalente a `evictions`.
5. O3 processou mais requisições e uma distribuição absoluta maior em todas as rotas. A normalização reduz, mas não elimina, o efeito da mistura e da concorrência.
6. Nesta comparação, O3 foi mais rápida que O2: req/s subiu de 1.52 para 2.31, p95 geral caiu de 33979.6 para 28249.7 ms e p95 D01 caiu de 32014.4 para 15331.2 ms.

### Relação com os benchmarks oficiais anteriores

Os benchmarks oficiais anteriores registraram o sentido oposto: O2→O3 teve req/s `2,98 → 1,91`, p95 geral `16.802,1 → 33.649,9 ms` e p95 D01 `16.084,4 → 19.494,6 ms`. Nesta investigação diagnóstica, a atividade adicional em `normal` e os `evictions` coexistiram com melhora de latência e vazão.

Portanto, a atividade de buffers observada é compatível com a presença e uso do índice, mas não é compatível, nesta amostra controlada, com a afirmação de que essa atividade tenha provocado degradação. A divergência entre os dois conjuntos reforça a variabilidade já documentada e impede usar um deles para invalidar o outro.

## Respostas à pergunta de investigação

1. **O3 apresentou mais leituras ou substituições?** Sim no contexto `normal`: a mediana passou de 122 para 8374 leituras e de 0 para 5197 `evictions`; por requisição, de 1.0446428571428572 para 54.37662337662338 leituras e de 0 para 33.746753246753244 `evictions`. Em `bulkread`, as leituras absolutas variaram apenas 0.7748523499925497% e diminuíram 27.61950539661393% por requisição.
2. **Há evidência consistente de maior pressão sobre shared_buffers?** Há evidência consistente de maior ocupação/substituição no caminho `normal`, não de aumento generalizado do volume de leituras: o trabalho de `bulkread` normalizado caiu e as leituras do heap de `itens_pedido` caíram. Os contadores não medem ocupação instantânea nem permitem atribuir cada substituição ao índice.
3. **O comportamento explica a regressão oficial?** Não. No teste controlado, O3 apresentou melhor desempenho apesar da atividade `normal` adicional.
4. **Fatores de confusão:** estado de cache e estatísticas após cada recriação; cache do sistema operacional não limpo; diferença de vazão e distribuição absoluta das rotas; concorrência entre rotas; atividades globais e internas capturadas por `pg_stat_io`; aquecimento e verificação de contrato dentro do intervalo; atraso de publicação das estatísticas; apenas três repetições; e `track_io_timing=off`.
5. **Avaliação da hipótese:** a hipótese causal completa — pressão adicional do índice contribuindo para a regressão O3 — foi **enfraquecida**. A primeira parte, maior atividade `normal`, foi observada; o efeito degradante não foi reproduzido. Isso não exclui influência do índice em outra condição de cache ou concorrência, mas não há evidência para atribuir a regressão oficial a ele.

## Limitações

- `pg_stat_io` é global ao servidor e não identifica automaticamente rota ou relação.
- `pg_statio_user_tables` e `pg_statio_user_indexes` são do banco atual, mas cobrem toda a atividade do intervalo, incluindo aquecimento e contrato executados pelo fluxo oficial.
- A documentação do PostgreSQL esclarece que leituras registradas não distinguem dados buscados do disco daqueles já presentes no cache de páginas do sistema operacional.
- `track_io_timing=off` impede comparar duração de I/O.
- `pg_buffercache` não estava habilitado e não foi instalado; não há fotografia de ocupação por relação.
- A recriação do banco foi necessária para aplicar/remover o SQL do índice e pode produzir diferenças de estado inicial.
- Não houve limpeza artificial de cache nem reset de estatísticas, conforme as restrições.
- Os tempos e contadores de cache não são decomposição da latência HTTP e não substituem `resumo.txt`.

## Fontes

- PostgreSQL 16, *Monitoring Statistics*: https://www.postgresql.org/docs/16/monitoring-stats.html
- pganalyze, *Index Advisor: Getting Started*: https://pganalyze.com/docs/index-advisor/getting-started

A documentação do PostgreSQL define `bulkread` como contexto usado por certas leituras grandes, define `evictions` de modo diferente em `normal` e nos contextos de anel, e define `reuses` como reutilização no anel limitado. A referência da pganalyze foi usada somente como motivação para avaliar competição de índices pelo buffer cache; nenhuma ferramenta pganalyze foi instalada ou executada.

## Caminhos das medições

O2:

- `resultados/20261120-215930-diag-cache-o2`
- `resultados/20261120-220651-diag-cache-o2`
- `resultados/20261120-221343-diag-cache-o2`

O3:

- `resultados/20261120-220316-diag-cache-o3`
- `resultados/20261120-221021-diag-cache-o3`
- `resultados/20261120-221707-diag-cache-o3`
