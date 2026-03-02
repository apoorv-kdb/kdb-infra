/ apps/sales/core/data_refresh.q
/ CONTRACT
/   Called by orchestrator as: .salesCore.refresh[dt; sources]
/   dt      — date being processed (kdb+ date)
/   sources — dict of sourceName -> filepath string
/   Must:
/     1. Load raw CSV via .csv.loadCSV (catalog drives rename + type cast)
/     2. Validate via .catalog.validate (blocking: missing cols; non-blocking: null counts)
/     3. Aggregate into cache tables
/     4. Write each date partition via .dbWriter.writeMultiple
/     5. Call .dbWriter.reload[]
/   On failure: call .ingestionLog.markFailed, return (::)

.salesCore.refresh:{[dt; sources]
  / 1. Load — catalog handles rename, drop unmapped, type cast
  txns:.csv.loadCSV[`sales_transactions; `sales; sources`sales_transactions; ","];

  / 2. Validate — blocking on missing columns, non-blocking on nulls
  vr:.catalog.validate[`sales_transactions; txns; `sales];

  if[not vr`valid;
    .ingestionLog.markFailed[`sales_transactions; dt; "; " sv vr`errors];
    :()];

  / Log null warnings (non-blocking — data still written)
  if[count vr`warnings;
    {show "  [WARN] ",x} each vr`warnings];

  / 3. Aggregate by date x region x product
  byRegion:0! select
      total_revenue:  sum revenue,
      total_quantity: sum quantity
    by date, region, product from txns;

  / 4. Write each distinct date to its own partition
  dates:asc distinct byRegion`date;
  {[txns; byRegion; d]
    txnDay:select from txns    where date = d;
    regDay:select from byRegion where date = d;
    .dbWriter.writeMultiple[`sales_transactions`sales_by_region!(txnDay; regDay); d];
  }[txns; byRegion;] each dates;

  / 5. Reload HDB
  .dbWriter.reload[];

  show "  Ingested ",string[count txns]," rows for ",string[count dates]," dates";
  / Mark each date completed with its own row count
  {[txns; src; d]
    n:count select from txns where date = d;
    .ingestionLog.markCompleted[src; d; n; ()]
  }[txns; `sales_transactions] each dates;
 }
