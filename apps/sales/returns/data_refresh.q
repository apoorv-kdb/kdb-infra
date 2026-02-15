/ sales/returns — data_refresh.q
/ Loads returns CSV, reads transactions from DB, computes net revenue by region

\d .sales.returns

refresh:{[dt; sources]

  / --- Load returns CSV ---
  returns:.csv.load[`sales_returns; sources`sales_returns; ","];

  / --- Read transactions from DB (already saved by sales_core) ---
  txns:select from sales_transactions where date = dt;

  / --- Aggregate returns by region ---
  retByRegion:select returned_quantity:sum quantity by date, region from returns;

  / --- Build net by region (start from transactions agg, join returns) ---
  netByRegion:select total_revenue:sum revenue, total_quantity:sum quantity
    by date, region from txns;
  netByRegion:netByRegion lj `date`region xkey retByRegion;
  netByRegion:update returned_quantity:0^returned_quantity from netByRegion;
  netByRegion:update net_quantity:total_quantity - returned_quantity from netByRegion;

  / --- Save ---
  .dbWriter.save[`sales_returns; returns; dt];
  .dbWriter.save[`sales_net_by_region; netByRegion; dt];
  .dbWriter.reload[];
 }

\d .
