/ inv/movements — config.q
/ Handles: daily movements → inbound/outbound/net by warehouse

/ ============================================================================
/ DOMAIN (already registered by positions, safe to call again)
/ ============================================================================

.dbWriter.addDomain[`inv];

/ ============================================================================
/ SOURCES
/ ============================================================================

.orchestrator.addSources[
  ((`source`app`required`directory`filePattern`delimiter`frequency)!
    (`inv_movements; `inv_movements; 1b; `:/data/csv; "inv_movements_*.csv"; ","; `daily))
 ];

/ ============================================================================
/ SCHEMAS — source
/ ============================================================================

.validator.registerSchema[`inv_movements;
  `columns`types`mandatory!(
    `date`warehouse`sku`direction`units`reason;
    "dssssj";
    `date`warehouse`sku`direction`units)
 ];

/ ============================================================================
/ SCHEMAS — derived
/ ============================================================================

.validator.registerSchema[`inv_movement_by_warehouse;
  `columns`types`mandatory!(
    `date`warehouse`inbound`outbound`net_movement;
    "dsjjj";
    `date`warehouse`inbound)
 ];

/ ============================================================================
/ RETENTION + REGISTER
/ ============================================================================

.retention.classifyBatch[
  `inv_movements`inv_movement_by_warehouse!
  `detailed`aggregated
 ];

.orchestrator.registerApp[`inv_movements; .inv.movements.refresh];
