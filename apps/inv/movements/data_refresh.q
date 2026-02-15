/ inv/movements — data_refresh.q
/ Loads movements, aggregates inbound/outbound/net by warehouse

\d .inv.movements

refresh:{[dt; sources]

  / --- Load ---
  movements:.csv.load[`inv_movements; sources`inv_movements; ","];

  / --- Aggregate by warehouse ---
  byWarehouse:select
    inbound:  sum units where direction = `IN,
    outbound: sum units where direction = `OUT
    by date, warehouse from movements;
  byWarehouse:update net_movement:inbound - outbound from byWarehouse;

  / --- Save ---
  .dbWriter.save[`inv_movements;              movements;   dt];
  .dbWriter.save[`inv_movement_by_warehouse;  byWarehouse; dt];
  .dbWriter.reload[];
 }

\d .
