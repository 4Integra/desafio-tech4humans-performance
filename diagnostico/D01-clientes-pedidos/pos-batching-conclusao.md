# Diagnóstico D01 após os batchings

## 1. Problema investigado

Verificar se as varreduras completas de 'pedidos' e 'itens_pedido' encontradas
na implementação original permanecem após os batchings de itens e produtos, qual
é o trabalho observado e se elas ainda podem contribuir para a latência de
'GET /clientes/:id/pedidos'.

Nas três medições oficiais da O2, D01 manteve medianas entre '11498.2' e
'12151.6 ms' e p95 entre '14591.5' e '17781.7 ms'.

## 2. Procedimento e parâmetros

Os comandos estão em
'diagnostico/D01-clientes-pedidos/pos-batching-comandos.sql'. Foi reutilizado o
caso mediano do diagnóstico original: cliente '3', pedidos '43262', '143262',
'243262', '343262' e '443262', e produtos únicos '125', '12886' e '13892'.

Cada consulta atual foi executada três vezes com
'EXPLAIN (ANALYZE, BUFFERS, SETTINGS)', em transação 'READ ONLY', com
'statement_timeout=30000 ms' e 'lock_timeout=2000 ms'.

## 3. Evidências

- Pedidos continua usando 'Parallel Seq Scan': remove '499995' linhas para
  devolver 5, acessa '20960' blocos e levou '122.493', '177.448' e
  '111.014 ms' nas três execuções isoladas.
- Itens em lote também usa 'Parallel Seq Scan': remove '1499985' linhas para
  devolver 15, acessa '9667' blocos e levou '284.516', '212.529' e
  '197.650 ms'.
- Produtos em lote usa 'Index Scan' em 'produtos_pkey', devolve os três produtos
  e levou '0.053', '0.095' e '0.078 ms'.
- Continuam ausentes índices em 'pedidos(cliente_id)' e
  'itens_pedido(pedido_id)'; somente os índices de chave primária foram
  encontrados.

Os planos e números completos estão em 'pos-batching-evidencias.txt'.

## 4. Comparação com o diagnóstico original

O batching não alterou o plano da consulta de pedidos. Na consulta de itens, a
varredura completa permanece, mas sua repetição caiu de cinco para uma por
requisição do caso mediano. A consulta de produtos continua indexada e sua
repetição caiu de até 15 para uma. A contagem derivada de consultas sequenciais
do caso mediano caiu de 22 para 4.

Logo, as otimizações reduziram operações repetidas, mas não eliminaram o trabalho
de varrer 'pedidos' e 'itens_pedido'.

## 5. Hipótese causal proporcional às evidências

Após os batchings, uma hipótese específica e testável é que a varredura completa
de 'pedidos' e a única varredura completa de 'itens_pedido' ainda contribuem para
a latência de D01 sob carga, porque cada requisição examina aproximadamente
500 mil pedidos e 1,5 milhão de itens e compete pelos recursos do PostgreSQL,
cuja CPU média permaneceu próxima do limite nas medições O2.

A evidência sustenta os scans como possível fator contribuinte, não como causa
exclusiva ou predominante da latência restante.

## 6. Limitações e condições de refutação

- Os tempos de 'EXPLAIN' foram obtidos isoladamente e não decompõem a latência
  HTTP sob 20 VUs.
- Cache e escalonamento variaram entre repetições e entre o diagnóstico original
  e o atual.
- A CPU é da carga mista; não mede exclusivamente D01.
- Conexão, fila, serialização e interferência de outras rotas não foram
  decompostas.
- O caso mediano não representa todas as possíveis cardinalidades.

A hipótese seria enfraquecida ou refutada se, em coleta controlada sob condições
comparáveis, a duração ou a espera associada aos dois scans não acompanhasse a
latência de D01, ou se outra etapa explicasse a maior parte da espera observada.
Com as evidências atuais, a magnitude da contribuição dos scans permanece
indeterminada.
