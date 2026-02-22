/ apps/sales/core - data_refresh.q
/ Loads transactions, aggregates by region, saves both

.salesCore.refresh:{[dt; sources]
  txns:.csv.loadCSV[`sales_transactions; sources`sales_transactions; ","];
  byRegion:0! select total_revenue:sum revenue, total_quantity:sum quantity, net_quantity:sum quantity
    by date, region from txns;
  .dbWriter.writeMultiple[`sales_transactions`sales_by_region!(txns; byRegion); dt];
  .dbWriter.reload[];
 }
