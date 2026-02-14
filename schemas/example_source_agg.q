/ example_source_agg.q
/ Schema definition for an example source aggregate dataset
/
/ Each schema file calls .validator.registerSchema to register its definition.
/ The name must match either:
/   - A source name in sources.q (for CSV-based tables)
/   - A table name used in db_writer.save (for derived tables)

/ Source table schema - validated on CSV load
.validator.registerSchema[`example_source_agg;
  `columns`types`mandatory!(
    `date`business`product`metric1`metric2;
    "dssff";
    `date`business`metric1
  )
 ];

/ Derived table schema (optional) - validated on db_writer.save
.validator.registerSchema[`example_by_business;
  `columns`types`mandatory!(
    `date`business`total_metric1`total_metric2;
    "dsff";
    `date`business`total_metric1
  )
 ];

/ ============================================================================
/ NOTES
/ ============================================================================
/ - Column order in `columns and `types must match
/ - Only columns listed in `columns will be kept from the CSV (extras dropped)
/ - Mandatory columns cause ingestion to fail if they contain nulls
/ - Type casting happens automatically based on `types
/
/ To add custom validation rules:
/
/ .validator.registerSchema[`my_source;
/   `columns`types`mandatory`rules!(
/     `date`amount`status;
/     "dfs";
/     `date`amount;
/     enlist `name`fn`params!("Amount positive"; {[data; params] .validator.inRange[data; `amount; 0; 1e12]}; ::)
/   )
/  ];
