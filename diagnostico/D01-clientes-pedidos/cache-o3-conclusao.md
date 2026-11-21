# Diagnóstico inicial de cache após O3

## Pergunta

A introdução de 'idx_itens_pedido_pedido_id' pode ter pressionado o cache do
PostgreSQL e prejudicado outras consultas durante a carga mista?

## Evidências observadas

A fotografia acumulada foi coletada em 21/11/2026 às 00:27:31 UTC. O PostgreSQL
está configurado com 'shared_buffers=128MB' e 'track_io_timing=off'.

O novo índice:

- tem 21 MB, equivalentes a 16,39% do tamanho configurado de shared_buffers;
- acumulou 177.441 scans, 9.289 blocos lidos e 523.279 hits;
- apresentou taxa derivada de hits de 98,26%.

Em pg_stat_io, os client backends acumularam:

| Contexto | Reads | Hits | Evictions | Reuses |
| --- | ---: | ---: | ---: | ---: |
| normal | 73.839 | 24.599.047 | 91.428 | NULL |
| bulkread | 2.544.467 | 2.363.250 | 11.872 | 2.528.900 |

Background workers também registraram reads e evictions em normal e bulkread.
Os contadores demonstram atividade de leitura e substituição no pool, mas são
globais e acumulados desde 20/11/2026 às 23:24:40 UTC.

No banco atual, o heap de pedidos acumulou 4.303.816 leituras e taxa derivada de
hits de 63,37%; itens_pedido acumulou 215.499 leituras e 95,68% de hits.

## Interpretação

O índice tem tamanho suficiente para ser uma parte não desprezível do conjunto
de páginas que compete por shared_buffers, e está sendo usado. A existência de
evictions e reuses torna a hipótese de pressão adicional plausível para
investigação controlada.

Entretanto, os valores absolutos não comparam O2 e O3. Eles incluem
inicialização, três cargas oficiais O3, verificações de contrato e diagnósticos
posteriores. Não há fotografia equivalente da O2 nem deltas por execução.

'reuses' em bulkread não é equivalente a 'evictions'. Leituras registradas pelo
PostgreSQL também podem ser atendidas pelo cache do sistema operacional e não
provam acesso físico obrigatório ao disco.

## Conclusão

Há indícios suficientes para justificar uma comparação controlada O2 × O3, mas
não para afirmar que o índice aumentou a pressão de cache ou causou a regressão.

O índice pode competir pelo pool, porém também apresenta alta taxa de hits e
melhora local comprovada na consulta de itens. Com as estatísticas disponíveis,
a influência líquida do índice sobre as outras consultas permanece
indeterminada.

## Limitações

- pg_stat_io é global ao cluster e acumulativo.
- As visões pg_statio são acumulativas no banco atual.
- track_io_timing está off; os tempos de I/O não estão disponíveis.
- pg_buffercache não está habilitado; não há ocupação instantânea por relação.
- Não existe snapshot equivalente da O2.
- Não há intervalo antes/depois delimitado para nenhuma execução.

## Comparação necessária

Para responder à pergunta, cada execução O2 e O3 deve ter snapshots imediatamente
antes e depois da carga, sem resetar estatísticas durante o experimento. Devem
ser comparados os deltas de:

- reads, hits e evictions em normal;
- reads, hits, evictions e reuses em bulkread;
- heap_blks_read/hit das tabelas relevantes;
- idx_blks_read/hit e uso do novo índice;
- p95, vazão, CPU e memória da mesma execução.

As configurações, dados, parâmetros e ordem devem ser controlados; a sequência
de configurações deve ser alternada para reduzir deriva temporal. Nenhuma dessas
comparações foi executada nesta etapa.

## Referências metodológicas

- https://www.postgresql.org/docs/16/monitoring-stats.html
- https://www.postgresql.org/docs/16/pgbuffercache.html
- https://pganalyze.com/docs/index-advisor/getting-started
