\set ON_ERROR_STOP on

BEGIN READ ONLY;
SET LOCAL statement_timeout = 30000;
SET LOCAL lock_timeout = 2000;

-- Contexto temporal e configurações.
SELECT clock_timestamp() AS coletado_em_utc,
       current_database() AS banco,
       version() AS versao;

SELECT pg_postmaster_start_time() AS servidor_iniciado_em_utc,
       current_setting('shared_buffers') AS shared_buffers,
       pg_size_bytes(current_setting('shared_buffers')) AS shared_buffers_bytes,
       current_setting('track_io_timing') AS track_io_timing;

SELECT datname,
       blks_read,
       blks_hit,
       temp_files,
       temp_bytes,
       stats_reset
FROM pg_stat_database
WHERE datname = current_database();

-- pg_stat_io é global ao cluster e acumulativa desde stats_reset.
SELECT backend_type,
       object,
       context,
       reads,
       hits,
       evictions,
       reuses,
       read_time,
       stats_reset
FROM pg_stat_io
ORDER BY backend_type, object, context;

-- Estatísticas acumuladas das tabelas do banco atual.
SELECT relname,
       heap_blks_read,
       heap_blks_hit,
       idx_blks_read,
       idx_blks_hit,
       toast_blks_read,
       toast_blks_hit
FROM pg_statio_user_tables
WHERE relname IN ('clientes', 'pedidos', 'itens_pedido', 'produtos')
ORDER BY relname;

-- Estatísticas acumuladas dos índices relevantes.
SELECT relname,
       indexrelname,
       idx_blks_read,
       idx_blks_hit
FROM pg_statio_user_indexes
WHERE relname IN ('clientes', 'pedidos', 'itens_pedido', 'produtos')
ORDER BY relname, indexrelname;

-- Contagem de uso do novo índice.
SELECT relname,
       indexrelname,
       idx_scan,
       last_idx_scan,
       idx_tup_read,
       idx_tup_fetch
FROM pg_stat_user_indexes
WHERE indexrelname = 'idx_itens_pedido_pedido_id';

-- Tamanhos das tabelas e dos índices relevantes.
SELECT c.relkind,
       c.relname,
       pg_relation_size(c.oid) AS relation_bytes,
       pg_size_pretty(pg_relation_size(c.oid)) AS relation_pretty,
       pg_total_relation_size(c.oid) AS total_bytes,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_pretty
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = current_schema()
  AND c.relname IN (
    'clientes',
    'pedidos',
    'itens_pedido',
    'produtos',
    'clientes_pkey',
    'pedidos_pkey',
    'itens_pedido_pkey',
    'idx_itens_pedido_pedido_id',
    'produtos_pkey'
  )
ORDER BY c.relkind, c.relname;

-- A extensão não será instalada. Se falso, não há fotografia de ocupação.
SELECT EXISTS (
  SELECT 1 FROM pg_extension WHERE extname = 'pg_buffercache'
) AS pg_buffercache_habilitado;

ROLLBACK;
