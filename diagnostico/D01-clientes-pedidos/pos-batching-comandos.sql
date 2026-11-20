\set ON_ERROR_STOP on

-- Diagnóstico pós-batching de D01, executado no HEAD d7861b96.
-- Parâmetros fixados antes dos EXPLAIN, usando o mesmo caso mediano do
-- diagnóstico original: cliente 3, cinco pedidos e três itens por pedido.
BEGIN READ ONLY;
SET LOCAL statement_timeout = 30000;
SET LOCAL lock_timeout = 2000;

-- Contexto e parâmetros reais usados nos planos.
SELECT id AS pedido_id, cliente_id, criado_em
FROM pedidos
WHERE cliente_id = 3
ORDER BY criado_em DESC, id DESC;

SELECT pedido_id, id AS item_id, produto_id
FROM itens_pedido
WHERE pedido_id = ANY(ARRAY[43262,143262,243262,343262,443262]::integer[])
ORDER BY pedido_id, id;

SELECT array_agg(DISTINCT produto_id ORDER BY produto_id) AS produto_ids
FROM itens_pedido
WHERE pedido_id = ANY(ARRAY[43262,143262,243262,343262,443262]::integer[]);

-- Índices disponíveis no momento do diagnóstico.
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = current_schema()
  AND tablename IN ('clientes', 'pedidos', 'itens_pedido', 'produtos')
ORDER BY tablename, indexname;

-- Consulta atual de pedidos: três repetições.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM pedidos
WHERE cliente_id = 3
ORDER BY criado_em DESC, id DESC;

EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM pedidos
WHERE cliente_id = 3
ORDER BY criado_em DESC, id DESC;

EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM pedidos
WHERE cliente_id = 3
ORDER BY criado_em DESC, id DESC;

-- Consulta atual de itens em lote: três repetições.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM itens_pedido
WHERE pedido_id = ANY(ARRAY[43262,143262,243262,343262,443262]::integer[])
ORDER BY pedido_id, id;

EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM itens_pedido
WHERE pedido_id = ANY(ARRAY[43262,143262,243262,343262,443262]::integer[])
ORDER BY pedido_id, id;

EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM itens_pedido
WHERE pedido_id = ANY(ARRAY[43262,143262,243262,343262,443262]::integer[])
ORDER BY pedido_id, id;

-- Consulta atual de produtos em lote: três repetições.
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM produtos
WHERE id = ANY(ARRAY[125,12886,13892]::integer[])
ORDER BY id;

EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM produtos
WHERE id = ANY(ARRAY[125,12886,13892]::integer[])
ORDER BY id;

EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM produtos
WHERE id = ANY(ARRAY[125,12886,13892]::integer[])
ORDER BY id;

ROLLBACK;
