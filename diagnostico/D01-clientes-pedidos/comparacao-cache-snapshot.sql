\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

BEGIN READ ONLY;
SET LOCAL statement_timeout = 30000;
SET LOCAL lock_timeout = 2000;

SELECT jsonb_pretty(jsonb_build_object(
  'coletado_em_utc', clock_timestamp(),
  'banco', current_database(),
  'servidor_iniciado_em_utc', pg_postmaster_start_time(),
  'shared_buffers', current_setting('shared_buffers'),
  'shared_buffers_bytes', pg_size_bytes(current_setting('shared_buffers')),
  'track_io_timing', current_setting('track_io_timing'),
  'pg_stat_database', (
    SELECT to_jsonb(s)
    FROM (
      SELECT datname,
             blks_read,
             blks_hit,
             temp_files,
             temp_bytes,
             stats_reset
      FROM pg_stat_database
      WHERE datname = current_database()
    ) s
  ),
  'pg_stat_io', (
    SELECT jsonb_agg(to_jsonb(s) ORDER BY backend_type, object, context)
    FROM (
      SELECT backend_type,
             object,
             context,
             reads,
             hits,
             evictions,
             reuses,
             stats_reset
      FROM pg_stat_io
    ) s
  ),
  'pg_statio_user_tables', (
    SELECT jsonb_agg(to_jsonb(s) ORDER BY relname)
    FROM (
      SELECT relname,
             heap_blks_read,
             heap_blks_hit,
             idx_blks_read,
             idx_blks_hit
      FROM pg_statio_user_tables
      WHERE relname IN ('clientes', 'pedidos', 'itens_pedido', 'produtos')
    ) s
  ),
  'pg_statio_user_indexes', (
    SELECT jsonb_agg(to_jsonb(s) ORDER BY relname, indexrelname)
    FROM (
      SELECT relname,
             indexrelname,
             idx_blks_read,
             idx_blks_hit
      FROM pg_statio_user_indexes
      WHERE relname IN ('clientes', 'pedidos', 'itens_pedido', 'produtos')
    ) s
  ),
  'pg_stat_user_indexes', (
    SELECT jsonb_agg(to_jsonb(s) ORDER BY relname, indexrelname)
    FROM (
      SELECT relname,
             indexrelname,
             idx_scan,
             idx_tup_read,
             idx_tup_fetch
      FROM pg_stat_user_indexes
      WHERE relname IN ('clientes', 'pedidos', 'itens_pedido', 'produtos')
    ) s
  )
));

ROLLBACK;
