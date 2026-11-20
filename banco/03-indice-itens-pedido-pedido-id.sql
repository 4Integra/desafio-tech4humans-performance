CREATE INDEX idx_itens_pedido_pedido_id
    ON itens_pedido USING btree (pedido_id);
