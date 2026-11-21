\set ON_ERROR_STOP on

-- Diagnóstico após O3, no HEAD a9d2cc0f.
-- Mesmo caso mediano dos diagnósticos anteriores.
BEGIN READ ONLY;
SET LOCAL statement_timeout = 30000;
SET LOCAL lock_timeout = 2000;

-- Índices e parâmetros fixados antes dos planos.
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = current_schema()
  AND tablename IN ('clientes', 'pedidos', 'itens_pedido', 'produtos')
ORDER BY tablename, indexname;

SELECT id AS pedido_id, cliente_id, criado_em
FROM pedidos
WHERE cliente_id = 3
ORDER BY criado_em DESC, id DESC;

SELECT pedido_id, id AS item_id, produto_id
FROM itens_pedido
WHERE pedido_id = ANY(ARRAY[43262,143262,243262,343262,443262]::integer[])
ORDER BY pedido_id, id;

-- Acesso por chave primária do cliente.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM clientes WHERE id = 3;

-- Pedidos do cliente: três repetições.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pedidos
WHERE cliente_id = 3
ORDER BY criado_em DESC, id DESC;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pedidos
WHERE cliente_id = 3
ORDER BY criado_em DESC, id DESC;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pedidos
WHERE cliente_id = 3
ORDER BY criado_em DESC, id DESC;

-- Itens dos cinco pedidos em lote: três repetições.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM itens_pedido
WHERE pedido_id = ANY(ARRAY[43262,143262,243262,343262,443262]::integer[])
ORDER BY pedido_id, id;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM itens_pedido
WHERE pedido_id = ANY(ARRAY[43262,143262,243262,343262,443262]::integer[])
ORDER BY pedido_id, id;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM itens_pedido
WHERE pedido_id = ANY(ARRAY[43262,143262,243262,343262,443262]::integer[])
ORDER BY pedido_id, id;

-- Produtos únicos do caso mediano.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM produtos
WHERE id = ANY(ARRAY[125,12886,13892]::integer[])
ORDER BY id;

ROLLBACK;
