# Próximos testes

As alternativas abaixo foram pesquisadas, mas não implementadas nem medidas. Os benefícios são hipóteses para experimentos futuros; não há estimativa de ganho. Cada mudança deve preservar o contrato HTTP, ser commitada isoladamente antes da carga e ser comparada por três medições com os mesmos parâmetros.

## Índice em `pedidos.cliente_id`

- **Fonte:** [PostgreSQL 16 — Introduction to Indexes](https://www.postgresql.org/docs/16/indexes-intro.html) e [CYBERTEC — Foreign Key Indexing and Performance](https://www.cybertec-postgresql.com/en/index-your-foreign-key/).
- **Benefício esperado:** permitir que a busca dos cinco pedidos de um cliente evite a varredura completa de `pedidos`, que permanece registrada nos diagnósticos atuais.
- **Como testar:** adicionar somente um índice B-tree em novo arquivo SQL de `banco/`; recriar bancos comparáveis; confirmar o plano com `EXPLAIN (ANALYZE, BUFFERS)`; verificar o contrato; executar três medições com rótulo próprio e comparar medianas com a configuração de referência escolhida.
- **Recursos e condições:** espaço do índice, participação no cache, custo de criação/manutenção e bancos com os mesmos dados e estado inicial. A medição deve separar o ganho local da consulta do resultado da carga mista.

## Pool de conexões do `node-postgres`

- **Fonte:** [node-postgres — Pooling](https://node-postgres.com/features/pooling).
- **Benefício esperado:** reutilizar conexões e evitar o handshake de abrir uma conexão por consulta, além de limitar explicitamente a concorrência enviada ao PostgreSQL.
- **Como testar:** substituir somente o ciclo atual de criação/encerramento de clientes por um único `pg.Pool`, com tamanho fixo e liberação garantida; manter as consultas e respostas; verificar o contrato; executar três medições e comparar p95, vazão, CPU, memória e quantidade de conexões.
- **Recursos e condições:** definir e registrar o tamanho do pool, observar espera por conexão e garantir encerramento correto. Pooling pode apenas deslocar a espera para uma fila; seu benefício precisa ser medido.

## Consulta única com `JOIN`

- **Fonte:** [PostgreSQL 16 — Table Expressions and Joined Tables](https://www.postgresql.org/docs/16/queries-table-expressions.html).
- **Benefício esperado:** buscar pedidos, itens e produtos em uma operação SQL, reduzindo viagens sequenciais entre API e banco. O ganho não é presumido: o conjunto intermediário, a ordenação e a montagem do JSON também podem ter custo.
- **Como testar:** implementar somente a consulta com `JOIN`; reconstruir exatamente a estrutura, os valores e a ordem do contrato; analisar o plano e cardinalidades; verificar as 42 respostas; executar três medições e comparar as medianas com a referência.
- **Recursos e condições:** controlar duplicação de linhas, ordenação de pedidos e itens, volume transferido e trabalho de serialização na API. CPU e memória dos dois serviços devem ser comparadas.

## Sequelize com associações e eager loading

- **Fonte:** [Sequelize v6 — Eager Loading](https://sequelize.org/docs/v6/advanced-association-concepts/eager-loading/).
- **Benefício esperado:** declarar relações e carregá-las com `include`, centralizando o gerenciamento de associações e evitando consultas relacionais dentro de laços.
- **Como testar:** criar um experimento isolado que introduza apenas o ORM e os modelos necessários; reproduzir o contrato byte a byte; registrar o SQL gerado e sua quantidade de consultas; executar três medições com os mesmos limites e comparar desempenho e recursos.
- **Recursos e condições:** nova dependência, tamanho de imagem, configuração do pool, custo de instanciação/serialização do ORM e compatibilidade com o esquema existente. Sequelize não deve ser considerado mais rápido sem medição.
