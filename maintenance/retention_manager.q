/ retention_manager.q
/ Enforce retention policy on partitions
/ Zone 1 (0-1yr): keep all daily
/ Zone 2 (1-2yr): keep 1st-of-month for detailed, keep all for aggregated
/ Zone 3 (2yr+): purge all except protected
/
/ Dependencies: db_writer.q

\d .retention

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

dailyRetentionDays:365
monthlyRetentionDays:730
tableClassification:()!()
protectedTables:enlist `infra_ingestion_log

setDailyRetention:{[days] `.retention.dailyRetentionDays set days}
setMonthlyRetention:{[days] `.retention.monthlyRetentionDays set days}

classify:{[tableName; classification]
  if[not classification in `detailed`aggregated;
    '"Classification must be `detailed or `aggregated"];
  .retention.tableClassification[tableName]:classification;
 }

classifyBatch:{[tableMap]
  .retention.tableClassification,:tableMap;
 }

getClass:{[tableName]
  if[tableName in protectedTables; :`protected];
  $[tableName in key tableClassification; tableClassification tableName; `detailed]
 }

/ ============================================================================
/ RETENTION LOGIC
/ ============================================================================

run:{[asOf]
  dbPath:.dbWriter.dbPath;
  allDates:asc "D"$string key dbPath;
  allDates:allDates where not null allDates;

  if[0 = count allDates; :`purged`kept!(0; 0)];

  oneYearAgo:asOf - dailyRetentionDays;
  twoYearsAgo:asOf - monthlyRetentionDays;

  zone1:allDates where allDates >= oneYearAgo;
  zone2:allDates where (allDates < oneYearAgo) & allDates >= twoYearsAgo;
  zone3:allDates where allDates < twoYearsAgo;

  / Zone 3: Purge all (except protected)
  if[count zone3;
    {[dbPath; dt] purgePartition[dbPath; dt]}[dbPath] each zone3];

  / Zone 2: Monthly snapshot logic for detailed tables
  if[count zone2;
    months:`month$zone2;
    byMonth:group months;
    {[dbPath; zone2; monthDates]
      datesInMonth:asc zone2 monthDates;
      keepDate:first datesInMonth;
      pruneDates:1 _ datesInMonth;
      {[dbPath; dt] pruneDetailedTables[dbPath; dt]}[dbPath] each pruneDates;
    }[dbPath; zone2] each value byMonth];

  `zone1Kept`zone2Dates`zone3Purged!(count zone1; count zone2; count zone3)
 }

/ ============================================================================
/ PARTITION OPERATIONS
/ ============================================================================

purgePartition:{[dbPath; dt]
  partPath:` sv dbPath , `$string dt;
  tables:key partPath;
  if[0 = count tables; :()];
  {[partPath; tbl]
    if[not `protected ~ getClass tbl;
      tblPath:` sv partPath , tbl;
      @[hdel; tblPath; {[e] show "Failed to delete: ",e}]];
  }[partPath] each tables;
 }

pruneDetailedTables:{[dbPath; dt]
  partPath:` sv dbPath , `$string dt;
  tables:key partPath;
  if[0 = count tables; :()];
  {[partPath; tbl]
    if[`detailed ~ getClass tbl;
      tblPath:` sv partPath , tbl;
      @[hdel; tblPath; {[e] show "Failed to delete: ",e}]];
  }[partPath] each tables;
 }

/ ============================================================================
/ DRY RUN
/ ============================================================================

dryRun:{[asOf]
  dbPath:.dbWriter.dbPath;
  allDates:asc "D"$string key dbPath;
  allDates:allDates where not null allDates;

  if[0 = count allDates; :([] date:`date$(); zone:`$(); action:`$(); detail:())];

  oneYearAgo:asOf - dailyRetentionDays;
  twoYearsAgo:asOf - monthlyRetentionDays;

  plan:([] date:`date$(); zone:`symbol$(); action:`symbol$(); detail:());

  {[plan; dt; oneYearAgo; twoYearsAgo; allDates]
    $[dt >= oneYearAgo;
      `plan insert (dt; `zone1_recent; `keep_all; "Within daily retention");
      dt >= twoYearsAgo;
      [
        monthDates:asc allDates where (`month$allDates) = `month$dt;
        $[dt = first monthDates;
          `plan insert (dt; `zone2_monthly; `keep_all; "Monthly snapshot - keep everything");
          `plan insert (dt; `zone2_monthly; `prune_detailed; "Remove detailed, keep aggregated")]
      ];
      `plan insert (dt; `zone3_old; `purge; "Beyond monthly retention - remove all except protected")];
    plan
  }[; ; oneYearAgo; twoYearsAgo; allDates]/[plan; allDates]
 }

\d .
