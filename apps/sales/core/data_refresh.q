/ apps/sales/core — data_refresh.q
/ Loads transactions, aggregates by region, saves both

.salesCore.refresh:{[dt; sources]

  / --- Load ---
  txns:.csv.loadCSV[`sales_transactions; sources`sales_transactions; ","];

  / --- Aggregate: by region ---
  byRegion:select total_revenue:sum revenue, total_quantity:sum quantity
    by date, region from txns;

  / --- Save ---
  .dbWriter.writePartition[`sales_transactions; txns; dt];
  .dbWriter.writePartition[`sales_by_region; byRegion; dt];
  .dbWriter.reload[];
 }
