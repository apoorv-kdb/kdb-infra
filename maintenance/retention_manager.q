/ retention_manager.q
/ Enforce retention policy on partitions
/ Zone 1 (0-1yr): keep all daily
/ Zone 2 (1-2yr): keep 1st-of-month for detailed, keep all for aggregated
/ Zone 3 (2yr+): purge all except protected
/ Dependencies: db_writer.q

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

.retention.dailyRetentionDays:365
.retention.monthlyRetentionDays:730
.retention.tableClassification:()!()
.retention.protectedTables:enlist `infra_ingestion_log

.retention.setDailyRetention:{[days] `.retention.dailyRetentionDays set days}
.retention.setMonthlyRetention:{[days] `.retention.monthlyRetentionDays set days}

.retention.classify:{[tblName; classification]
  if[not classification in `detailed`aggregated;
    '"Classification must be `detailed or `aggregated"];
  .retention.tableClassification[tblName]:classification;
 }

.retention.classifyBatch:{[tableMap]
  .retention.tableClassification,:tableMap;
 }

.retention.getClass:{[tblName]
  if[tblName in .retention.protectedTables; :`protected];
  $[tblName in key .retention.tableClassification; .retention.tableClassification tblName; `detailed]
 }

/ ============================================================================
/ RETENTION LOGIC
/ ============================================================================

.retention.execute:{[asOf]
  dbPath:.dbWriter.dbPath;
  allDates:asc "D"$string key dbPath;
  allDates:allDates where not null allDates;

  if[0 = count allDates; :`purged`kept!(0; 0)];

  oneYearAgo:asOf - .retention.dailyRetentionDays;
  twoYearsAgo:asOf - .retention.monthlyRetentionDays;

  zone1:allDates where allDates >= oneYearAgo;
  zone2:allDates where (allDates < oneYearAgo) & allDates >= twoYearsAgo;
  zone3:allDates where allDates < twoYearsAgo;

  / Zone 3: Purge all (except protected)
  if[count zone3;
    {[dbPath; dt] .retention.purgePartition[dbPath; dt]}[dbPath] each zone3];

  / Zone 2: Monthly snapshot logic for detailed tables
  if[count zone2;
    months:`month$zone2;
    byMonth:group months;
    {[dbPath; zone2; monthDates]
      datesInMonth:asc zone2 monthDates;
      pruneDates:1 _ datesInMonth;
      {[dbPath; dt] .retention.pruneDetailedTables[dbPath; dt]}[dbPath] each pruneDates;
    }[dbPath; zone2] each value byMonth];

  `zone1Kept`zone2Dates`zone3Purged!(count zone1; count zone2; count zone3)
 }

/ ============================================================================
/ PARTITION OPERATIONS
/ ============================================================================

.retention.purgePartition:{[dbPath; dt]
  partPath:` sv dbPath , `$string dt;
  tbls:key partPath;
  if[0 = count tbls; :()];
  {[partPath; tbl]
    if[not `protected ~ .retention.getClass tbl;
      tblPath:` sv partPath , tbl;
      @[hdel; tblPath; {[e] show "Failed to delete: ",e}]];
  }[partPath] each tbls;
 }

.retention.pruneDetailedTables:{[dbPath; dt]
  partPath:` sv dbPath , `$string dt;
  tbls:key partPath;
  if[0 = count tbls; :()];
  {[partPath; tbl]
    if[`detailed ~ .retention.getClass tbl;
      tblPath:` sv partPath , tbl;
      @[hdel; tblPath; {[e] show "Failed to delete: ",e}]];
  }[partPath] each tbls;
 }

/ ============================================================================
/ DRY RUN
/ ============================================================================

.retention.dryRun:{[asOf]
  dbPath:.dbWriter.dbPath;
  allDates:asc "D"$string key dbPath;
  allDates:allDates where not null allDates;

  if[0 = count allDates; :([] date:`date$(); zone:`$(); action:`$(); detail:())];

  oneYearAgo:asOf - .retention.dailyRetentionDays;
  twoYearsAgo:asOf - .retention.monthlyRetentionDays;

  {[oneYearAgo; twoYearsAgo; allDates; plan; dt]
    $[dt >= oneYearAgo;
      plan , ([] date:enlist dt; zone:enlist `zone1_recent; action:enlist `keep_all; detail:enlist "Within daily retention");
      dt >= twoYearsAgo;
      [
        monthDates:asc allDates where (`month$allDates) = `month$dt;
        $[dt = first monthDates;
          plan , ([] date:enlist dt; zone:enlist `zone2_monthly; action:enlist `keep_all; detail:enlist "Monthly snapshot - keep everything");
          plan , ([] date:enlist dt; zone:enlist `zone2_monthly; action:enlist `prune_detailed; detail:enlist "Remove detailed, keep aggregated")]
      ];
      plan , ([] date:enlist dt; zone:enlist `zone3_old; action:enlist `purge; detail:enlist "Beyond monthly retention - remove all except protected")]
  }[oneYearAgo; twoYearsAgo; allDates]/[([] date:`date$(); zone:`symbol$(); action:`symbol$(); detail:()); allDates]
 }
