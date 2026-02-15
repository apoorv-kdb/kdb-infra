/ inv/positions — config.q
/ Handles: daily positions → enriched with ref data, aggregated by warehouse + category

/ ============================================================================
/ DOMAIN
/ ============================================================================

.dbWriter.addDomain[`inv];

/ ============================================================================
/ SOURCES
/ ============================================================================

.orchestrator.addSources[
  ((`source`app`required`directory`filePattern`delimiter`frequency)!
    (`inv_positions; `inv_positions; 1b; `:/data/csv; "inv_positions_*.csv"; ","; `daily))
 ];

/ ============================================================================
/ SCHEMAS — source
/ ============================================================================

.validator.registerSchema[`inv_positions;
  `columns`types`mandatory!(
    `date`warehouse`category`subcategory`sku`units`value;
    "dssssji";
    `date`warehouse`sku`units`value)
 ];

/ ============================================================================
/ SCHEMAS — derived
/ ============================================================================

.validator.registerSchema[`inv_by_warehouse;
  `columns`types`mandatory!(
    `date`warehouse`region`total_units`total_value;
    "dssji";
    `date`warehouse`total_units`total_value)
 ];

.validator.registerSchema[`inv_by_category;
  `columns`types`mandatory!(
    `date`category`total_units`total_value;
    "dsji";
    `date`category`total_units)
 ];

/ ============================================================================
/ RETENTION + REGISTER
/ ============================================================================

.retention.classifyBatch[
  `inv_positions`inv_by_warehouse`inv_by_category!
  `detailed`aggregated`aggregated
 ];

.orchestrator.registerApp[`inv_positions; .inv.positions.refresh];
