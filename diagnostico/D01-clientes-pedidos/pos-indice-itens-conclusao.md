# Diagnóstico D01 após o índice de itens

## Problema investigado

A O3 adicionou um índice B-tree em 'itens_pedido(pedido_id)', mas as medições
oficiais apresentaram, contra a O2, queda de 35,91% na vazão, aumento de 100,27%
no p95 geral e aumento de 21,20% no p95 D01. A investigação verificou se a
consulta-alvo usa o índice e se a regressão pode ser atribuída a ela.

## Evidências da consulta de itens

Com os mesmos cinco pedidos dos diagnósticos anteriores, o plano mudou de
'Parallel Seq Scan' para 'Index Scan using idx_itens_pedido_pedido_id', seguido
de 'Incremental Sort'.

- Antes: mediana isolada de 212,529 ms, 9.667 buffers e 1.499.985 linhas
  removidas por filtro.
- Depois: mediana isolada de 0,099 ms, 20 buffers e nenhuma varredura completa.

As três execuções atuais levaram 0,075, 0,127 e 0,099 ms. Portanto, o índice foi
utilizado e reduziu substancialmente o trabalho isolado da consulta de itens.

## Trabalho relevante que permanece

A consulta de pedidos do cliente continua usando 'Parallel Seq Scan'. Para
devolver cinco pedidos, remove 499.995 linhas, acessa 20.960 buffers e teve
mediana isolada de 181,061 ms.

Cliente e produtos usam seus índices de chave primária. O caminho atual de D01
executa quatro consultas sequenciais; cada uma ainda abre uma conexão
PostgreSQL independente.

Nos resultados oficiais O3, o PostgreSQL permaneceu próximo do limite de CPU.
Também foram observados p95 medianos de 43.780,2 ms em pedidos-por-status,
38.233,2 ms em vendas-por-dia e 56.240,3 ms em top-produtos, além de timeouts
fora de D01.

## Interpretação da regressão O3

Os planos refutam a interpretação de que a consulta indexada de itens ficou mais
cara: ela passou a usar o índice, com menos buffers e menor tempo isolado.

Por outro lado, os EXPLAIN isolados não explicam diretamente o benchmark misto.
A regressão O2 para O3 coincidiu com lentidão e timeouts em outras rotas, e a
CPU do banco permaneceu elevada. Não há evidência suficiente para afirmar que o
índice, isoladamente, causou a regressão.

## Hipótese atual

Uma hipótese específica e testável é que a latência restante de D01 seja
ampliada por espera e contenção no PostgreSQL sob a carga mista; dentro do
caminho de D01, a varredura completa de 'pedidos' por 'cliente_id' é o trabalho
SQL isolado mais relevante que permanece.

A evidência sustenta essa hipótese como possibilidade, não como causa exclusiva
ou predominante. A causa específica da regressão entre O2 e O3 permanece
inconclusiva.

## Limitações e refutação

- Os planos foram obtidos sem a concorrência da carga oficial.
- Cache, fila, conexão e interferência entre rotas não foram decompostos.
- CPU e memória representam a carga mista.
- D01 teve poucas amostras por execução.

A hipótese seria enfraquecida se uma medição controlada mostrasse que a espera
de D01 não acompanha a contenção do banco, ou se a consulta de pedidos
representasse parcela irrelevante do tempo sob condições comparáveis. A
regressão O3 só poderia ser atribuída ao índice com evidência controlada que
isolasse essa mudança da variabilidade do restante da carga.
