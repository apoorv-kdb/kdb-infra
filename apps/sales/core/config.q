/ apps/sales/core/config.q
/ Registers sources and app with the orchestrator.
/ Schema definitions removed — catalog CSV is the single source of truth.

.dbWriter.addDomain[`sales];

/ ============================================================================
/ SOURCES
/ ============================================================================

/ csvDir — resolved from argCsvPath set by orchestrator startup.
/ Data lives OUTSIDE the code folder by design — never under ROOT.
csvDir:$[`argCsvPath in key `.;  argCsvPath;
         `csvPath in key .Q.opt .z.x; first (.Q.opt .z.x)`csvPath;
         "C:/data/csv"];

.orchestrator.addSources[
  ((`source`app`required`directory`filePattern`delimiter`frequency)!
    (`sales_transactions; `sales; 1b; hsym `$csvDir; `$"sales_transactions_*.csv"; ","; `daily))
 ];

/ ============================================================================
/ REGISTER
/ ============================================================================

.orchestrator.registerApp[`sales; .salesCore.refresh];
