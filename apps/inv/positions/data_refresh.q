/ inv/positions — data_refresh.q
/ Loads positions, enriches with warehouse ref, aggregates by warehouse + category

\d .inv.positions

refresh:{[dt; sources]

  / --- Load ---
  positions:.csv.load[`inv_positions; sources`inv_positions; ","];

  / --- Load ref data ---
  warehouseRef:("SSS"; enlist ",") 0: `:/data/ref/warehouse_ref.csv;

  / --- Enrich with ref data ---
  enriched:positions lj `warehouse xkey warehouseRef;

  / --- Aggregate: by warehouse ---
  byWarehouse:select total_units:sum units, total_value:sum value
    by date, warehouse, region from enriched;

  / --- Aggregate: by category ---
  byCategory:select total_units:sum units, total_value:sum value
    by date, category from positions;

  / --- Save ---
  .dbWriter.save[`inv_positions;    positions;    dt];
  .dbWriter.save[`inv_by_warehouse; byWarehouse;  dt];
  .dbWriter.save[`inv_by_category;  byCategory;   dt];
  .dbWriter.reload[];
 }

\d .
