#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 6 ]]; then
  echo "uso: bash comparacao-cache-rodada.sh <worktree> <config> <commit> <indice:0|1> <snapshot-dir> <rotulo>" >&2
  exit 2
fi

WORKTREE="$1"
CONFIG="$2"
COMMIT_ESPERADO="$3"
INDICE_ESPERADO="$4"
SNAP_DIR="$5"
LABEL="$6"
MAIN_ROOT="/home/kakau/meu-desafio"
SNAPSHOT_SQL="$MAIN_ROOT/diagnostico/D01-clientes-pedidos/comparacao-cache-snapshot.sql"

cd "$WORKTREE"
mkdir -p "$SNAP_DIR"

HEAD_ATUAL="$(git rev-parse HEAD)"
if [[ "$HEAD_ATUAL" != "$COMMIT_ESPERADO" ]]; then
  echo "HEAD inesperado: $HEAD_ATUAL" >&2
  exit 1
fi

PENDENCIAS="$(git status --porcelain -- . ':(exclude)resultados')"
if [[ -n "$PENDENCIAS" ]]; then
  echo "arquivos pendentes fora de resultados:" >&2
  echo "$PENDENCIAS" >&2
  exit 1
fi

docker compose down -v
docker compose up -d --build

API_PRONTA=0
for tentativa in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:3000/saude > /dev/null 2>&1; then
    API_PRONTA=1
    break
  fi
  sleep 2
done
[[ "$API_PRONTA" -eq 1 ]]

INDEX_COUNT="$(docker compose exec -T banco psql -X -At -U loja -d loja -c "SELECT count(*) FROM pg_indexes WHERE schemaname='public' AND indexname='idx_itens_pedido_pedido_id';")"
if [[ "$INDEX_COUNT" != "$INDICE_ESPERADO" ]]; then
  echo "presença inesperada do índice: $INDEX_COUNT" >&2
  exit 1
fi

DATA_COUNTS="$(docker compose exec -T banco psql -X -At -U loja -d loja -c "SELECT (SELECT count(*) FROM clientes), (SELECT count(*) FROM pedidos), (SELECT count(*) FROM itens_pedido), (SELECT count(*) FROM produtos);")"
if [[ "$DATA_COUNTS" != "100000|500000|1500000|20000" ]]; then
  echo "cardinalidades inesperadas: $DATA_COUNTS" >&2
  exit 1
fi

{
  echo "configuracao=$CONFIG"
  echo "commit=$HEAD_ATUAL"
  echo "indice_presente=$INDEX_COUNT"
  echo "cardinalidades=$DATA_COUNTS"
  echo "shared_buffers=$(docker compose exec -T banco psql -X -At -U loja -d loja -c 'SHOW shared_buffers;')"
  echo "track_io_timing=$(docker compose exec -T banco psql -X -At -U loja -d loja -c 'SHOW track_io_timing;')"
  docker compose ps
  for servico in api banco; do
    id="$(docker compose ps -q "$servico")"
    docker inspect --format "$servico: cpus={{.HostConfig.NanoCpus}} memoria={{.HostConfig.Memory}}" "$id"
  done
} > "$SNAP_DIR/setup.txt"

scripts/verificar-contrato.sh comparar > "$SNAP_DIR/contrato-antes.txt"
if ! tail -n 1 "$SNAP_DIR/contrato-antes.txt" | grep -q "Contrato mantido"; then
  echo "contrato não mantido antes da medição" >&2
  exit 1
fi

docker compose exec -T banco psql -X -qAt -U loja -d loja < "$SNAPSHOT_SQL" > "$SNAP_DIR/antes.json"

scripts/medir.sh "$LABEL" | tee "$SNAP_DIR/medir-console.txt"

sleep 2
docker compose exec -T banco psql -X -qAt -U loja -d loja < "$SNAPSHOT_SQL" > "$SNAP_DIR/depois.json"

RESULT_DIR="$(find resultados -maxdepth 1 -type d -name "*-$LABEL" -printf '%p\n' | sort | tail -n 1)"
if [[ -z "$RESULT_DIR" ]]; then
  echo "pasta de resultado não encontrada" >&2
  exit 1
fi

for arquivo in resumo.txt resumo-k6.json recursos.txt recursos.csv contexto.txt contrato.txt; do
  test -f "$RESULT_DIR/$arquivo"
done

grep -Fxq "arquivos alterados sem commit: 0" "$RESULT_DIR/contexto.txt"
grep -Fxq "commit: $(git rev-parse --short HEAD)" "$RESULT_DIR/contexto.txt"
tail -n 1 "$RESULT_DIR/contrato.txt" | grep -q "Contrato mantido"

printf '%s\n' "$RESULT_DIR" > "$SNAP_DIR/resultado-path.txt"
echo "RODADA_OK config=$CONFIG resultado=$RESULT_DIR"
