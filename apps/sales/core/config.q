/ apps/sales/core — config.q
/ Handles: daily transactions, saves detail + regional aggregation

/ ============================================================================
/ DOMAIN
/ ============================================================================

.dbWriter.addDomain[`sales];

/ ============================================================================
/ SOURCES
/ ============================================================================

.orchestrator.addSources[
  ((`source`app`required`directory`filePattern`delimiter`frequency)!
    (`sales_transactions; `sales_core; 1b; `:/data/csv; "sales_transactions_*.csv"; ","; `daily))
 ];

/ ============================================================================
/ SCHEMAS — source
/ ============================================================================

.validator.registerSchema[`sales_transactions;
  `columns`types`mandatory!(
    `date`region`product`quantity`revenue;
    "DSSJI";
    `date`region`product`revenue)
 ];

/ ============================================================================
/ SCHEMAS — derived
/ ============================================================================

.validator.registerSchema[`sales_by_region;
  `columns`types`mandatory!(
    `date`region`total_revenue`total_quantity;
    "DSJI";
    `date`region`total_revenue)
 ];

/ ============================================================================
/ RETENTION + REGISTER
/ ============================================================================

.retention.classifyBatch[`sales_transactions`sales_by_region!`detailed`aggregated];

.orchestrator.registerApp[`sales_core; .salesCore.refresh];
