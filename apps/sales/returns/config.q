/ sales/returns — config.q
/ Handles: returns data → net revenue by region (joins with transactions)

/ ============================================================================
/ DOMAIN (already registered by core, safe to call again)
/ ============================================================================

.dbWriter.addDomain[`sales];

/ ============================================================================
/ SOURCES
/ ============================================================================

.orchestrator.addSources[
  ((`source`app`required`directory`filePattern`delimiter`frequency)!
    (`sales_returns; `sales_returns; 1b; `:/data/csv; "sales_returns_*.csv"; ","; `daily))
 ];

/ ============================================================================
/ SCHEMAS — source
/ ============================================================================

.validator.registerSchema[`sales_returns;
  `columns`types`mandatory!(
    `date`region`product`quantity`reason;
    "dssjS";
    `date`region`product)
 ];

/ ============================================================================
/ SCHEMAS — derived
/ ============================================================================

.validator.registerSchema[`sales_net_by_region;
  `columns`types`mandatory!(
    `date`region`total_revenue`total_quantity`returned_quantity`net_quantity;
    "dsijjj";
    `date`region`total_revenue)
 ];

/ ============================================================================
/ RETENTION + REGISTER
/ ============================================================================

.retention.classifyBatch[`sales_returns`sales_net_by_region!`detailed`aggregated];

.orchestrator.registerApp[`sales_returns; .sales.returns.refresh];
