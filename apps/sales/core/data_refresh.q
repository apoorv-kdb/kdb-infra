/ apps/sales/core - data_refresh.q
/ Loads transactions, aggregates by region, saves both

.salesCore.refresh:{[dt; sources]
  txns:.csv.loadCSV[`sales_transactions; sources`sales_transactions; ","];
  byRegion:0! select total_revenue:sum revenue, total_quantity:sum quantity, net_quantity:sum quantity
    by date, region from txns;
  / Write each date to its own partition
  dates:asc distinct byRegion`date;
  {[txns; byRegion; d]
    txnDay:  select from txns   where date=d;
    regDay:  select from byRegion where date=d;
    .dbWriter.writeMultiple[`sales_transactions`sales_by_region!(txnDay; regDay); d];
  }[txns; byRegion;] each dates;
  .dbWriter.reload[];
 }
