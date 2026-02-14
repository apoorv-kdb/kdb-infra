/ sources.q
/ Maps each data source to its app, file location, pattern, and dependency type
/ Edit this file to onboard new sources - no other code changes needed

source_config:([]
  source:`symbol$();
  app:`symbol$();
  required:`boolean$();
  directory:`symbol$();
  filePattern:();
  delimiter:();
  frequency:`symbol$()
 )

/ ============================================================================
/ EXAMPLE: Uncomment and modify for your sources
/ ============================================================================

/ `source_config insert (`app1_source_agg;  `app1; 1b; `:/data/csv; "app1_agg_*.csv";     ","; `daily);
/ `source_config insert (`app1_detail;       `app1; 1b; `:/data/csv; "app1_detail_*.csv";   ","; `daily);
/ `source_config insert (`app1_positions;    `app1; 0b; `:/data/csv; "app1_pos_*.csv";      ","; `daily);
/ `source_config insert (`app2_source_agg;   `app2; 1b; `:/data/csv; "app2_summary_*.csv";  ","; `daily);
