/ sales/core — data_refresh.q
/ Loads transactions, aggregates by region, saves both

\d .sales.core

refresh:{[dt; sources]

  / --- Load ---
  txns:.csv.load[`sales_transactions; sources`sales_transactions; ","];

  / --- Aggregate: by region ---
  byRegion:select total_revenue:sum revenue, total_quantity:sum quantity
    by date, region from txns;

  / --- Save ---
  .dbWriter.save[`sales_transactions; txns; dt];
  .dbWriter.save[`sales_by_region; byRegion; dt];
  .dbWriter.reload[];
 }

\d .
