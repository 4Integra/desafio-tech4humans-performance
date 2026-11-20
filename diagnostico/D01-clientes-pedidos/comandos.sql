\set ON_ERROR_STOP on

BEGIN READ ONLY;
SET LOCAL statement_timeout = 30000;
SET LOCAL lock_timeout = 2000;

-- Cardinalidades globais.
SELECT
  (SELECT count(*) FROM clientes) AS clientes,
  (SELECT count(*) FROM pedidos) AS pedidos,
  (SELECT count(*) FROM itens_pedido) AS itens_pedido,
  (SELECT count(*) FROM produtos) AS produtos;

-- Distribuição de pedidos por cliente.
SELECT min(n) AS min_pedidos,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY n) AS mediana_pedidos,
       max(n) AS max_pedidos,
       avg(n) AS media_pedidos
FROM (
  SELECT c.id, count(p.id)::integer AS n
  FROM clientes c
  LEFT JOIN pedidos p ON p.cliente_id = c.id
  GROUP BY c.id
) s;

-- Distribuição de itens por pedido.
SELECT min(n) AS min_itens,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY n) AS mediana_itens,
       max(n) AS max_itens,
       avg(n) AS media_itens
FROM (
  SELECT p.id, count(i.id)::integer AS n
  FROM pedidos p
  LEFT JOIN itens_pedido i ON i.pedido_id = p.id
  GROUP BY p.id
) s;

-- Seleção determinística: menor cliente com 1, 3 e 5 itens por pedido.
WITH por_pedido AS (
  SELECT p.cliente_id, p.id AS pedido_id, count(i.id)::integer AS itens
  FROM pedidos p
  JOIN itens_pedido i ON i.pedido_id = p.id
  GROUP BY p.cliente_id, p.id
), por_cliente AS (
  SELECT cliente_id, min(itens) AS min_itens, max(itens) AS max_itens
  FROM por_pedido
  GROUP BY cliente_id
)
SELECT min(cliente_id) FILTER (WHERE min_itens = 1 AND max_itens = 1) AS cliente_1_item,
       min(cliente_id) FILTER (WHERE min_itens = 3 AND max_itens = 3) AS cliente_3_itens,
       min(cliente_id) FILTER (WHERE min_itens = 5 AND max_itens = 5) AS cliente_5_itens
FROM por_cliente;

-- Pedidos e itens dos parâmetros selecionados.
SELECT p.cliente_id, p.id AS pedido_id, count(i.id) AS itens
FROM pedidos p
JOIN itens_pedido i ON i.pedido_id = p.id
WHERE p.cliente_id IN (1, 3, 5)
GROUP BY p.cliente_id, p.id
ORDER BY p.cliente_id, p.criado_em DESC, p.id DESC;

-- Índices existentes.
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = current_schema()
ORDER BY tablename, indexname;

-- Primeiro pedido do cliente mediano na ordem da rota: 43262.
SELECT id, pedido_id, produto_id, quantidade, preco_unitario_centavos
FROM itens_pedido
WHERE pedido_id = 43262
ORDER BY id;

-- Planos das quatro consultas executadas pela rota.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM clientes WHERE id = 3;

-- Três repetições da consulta de pedidos.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM pedidos WHERE cliente_id = 3 ORDER BY criado_em DESC, id DESC;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM pedidos WHERE cliente_id = 3 ORDER BY criado_em DESC, id DESC;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM pedidos WHERE cliente_id = 3 ORDER BY criado_em DESC, id DESC;

-- Três repetições da consulta de itens.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM itens_pedido WHERE pedido_id = 43262 ORDER BY id;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM itens_pedido WHERE pedido_id = 43262 ORDER BY id;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM itens_pedido WHERE pedido_id = 43262 ORDER BY id;

EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM produtos WHERE id = 12886;

ROLLBACK;
