/ apps/sales/core — config.q
/ Handles: daily transactions, saves detail + regional aggregation

/ ============================================================================
/ DOMAIN
/ ============================================================================

.dbWriter.addDomain[`sales];

/ ============================================================================
/ SOURCES
/ ============================================================================

/ Directory defaults to <ROOT>/data/csv — pass -csvPath on command line to override
csvDir:$[`csvPath in key .Q.opt .z.x; first (.Q.opt .z.x)`csvPath; ROOT,"/data/csv"];

.orchestrator.addSources[
  ((`source`app`required`directory`filePattern`delimiter`frequency)!
    (`sales_transactions; `sales_core; 1b; hsym `$csvDir; `$"sales_transactions_*.csv"; ","; `daily))
 ];

/ ============================================================================
/ SCHEMAS - source
/ ============================================================================

.validator.registerSchema[`sales_transactions;
  `columns`types`mandatory!(
    `date`region`product`quantity`revenue;
    "DSSJI";
    `date`region`product`revenue)
 ];

/ ============================================================================
/ SCHEMAS - derived
/ ============================================================================

.validator.registerSchema[`sales_by_region;
  `columns`types`mandatory!(
    `date`region`total_revenue`total_quantity`net_quantity;
    "DSJJJ";
    `date`region`total_revenue)
 ];

/ ============================================================================
/ REGISTER
/ ============================================================================

.orchestrator.registerApp[`sales_core; .salesCore.refresh];
