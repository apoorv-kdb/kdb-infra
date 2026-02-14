/ comparison.q
/ Period-over-period comparison and delta calculations
/ Day-over-day, month-over-month, custom period deltas
/
/ Takes two snapshots (current and previous) and computes differences.
/ Works with any table shape - just specify which columns are metrics.
/
/ Stateless: tables in, table out

\d .comparison

/ ============================================================================
/ CORE DELTA
/ ============================================================================

/ Compute deltas between two tables (current vs previous)
/ Tables must have the same key columns. Metrics are differenced.
/ Args:
/   current: table - current period data
/   previous: table - previous period data
/   keyCols: symbol list - columns to join on (e.g. `business`product)
/   metricCols: symbol list - columns to difference
/ Returns: table with keyCols + for each metric: current, previous, change, changePct
delta:{[current; previous; keyCols; metricCols]
  / Rename previous metrics to avoid collision
  prevRenamed:renameMetrics[previous; metricCols; "_prev"];

  / Join on key columns
  joined:current lj `keyCols xkey prevRenamed;

  / Compute change and pct for each metric
  {[t; mc]
    prevCol:`$string[mc],"_prev";
    chgCol:`$string[mc],"_chg";
    pctCol:`$string[mc],"_pct";

    curVals:t mc;
    prevVals:t prevCol;
    chg:curVals - prevVals;
    pct:?[prevVals = 0; 0Nf; chg % prevVals];

    t:![t; (); 0b; (enlist chgCol)!(enlist chg)];
    t:![t; (); 0b; (enlist pctCol)!(enlist pct)];
    t
  }/[joined; metricCols]
 }

/ Simplified delta: same table, two dates
/ Extracts current and previous slices, then computes delta
/ Args:
/   data: table with date column
/   currentDate: date
/   previousDate: date
/   keyCols: symbol list - non-date key columns
/   metricCols: symbol list
/ Returns: delta table
deltaByDate:{[data; currentDate; previousDate; keyCols; metricCols]
  current:select from data where date = currentDate;
  previous:select from data where date = previousDate;
  / Drop date column for the join since dates differ
  current:keyCols,metricCols#current;
  previous:keyCols,metricCols#previous;
  result:delta[current; previous; keyCols; metricCols];
  result:([] currentDate:count[result]#currentDate; previousDate:count[result]#previousDate),'result;
  result
 }

/ ============================================================================
/ AGGREGATE COMPARISONS
/ ============================================================================

/ Compare totals between two periods
/ Args:
/   current: table
/   previous: table
/   metricCols: symbol list
/ Returns: single-row table with total current, previous, change, pct for each metric
totalDelta:{[current; previous; metricCols]
  curTotals:{[d; mc] sum d mc}[current] each metricCols;
  prevTotals:{[d; mc] sum d mc}[previous] each metricCols;

  result:1#([] dummy:enlist 0);
  result:{[t; mc; cv; pv]
    chg:cv - pv;
    pct:$[pv = 0; 0Nf; chg % pv];
    t:![t; (); 0b; (enlist mc)!(enlist cv)];
    t:![t; (); 0b; (enlist `$string[mc],"_prev")!(enlist pv)];
    t:![t; (); 0b; (enlist `$string[mc],"_chg")!(enlist chg)];
    t:![t; (); 0b; (enlist `$string[mc],"_pct")!(enlist pct)];
    t
  }/[result; metricCols; curTotals; prevTotals];

  ![result; (); 0b; enlist `dummy]
 }

/ ============================================================================
/ MOVERS
/ ============================================================================

/ Find top N movers by absolute change
/ Args:
/   deltaTable: output of delta function
/   metricCol: symbol - which metric's change column to rank by
/   n: int - top N
/ Returns: table sorted by absolute change descending, top N rows
topMovers:{[deltaTable; metricCol; n]
  chgCol:`$string[metricCol],"_chg";
  deltaTable:update absChg:abs deltaTable[chgCol] from deltaTable;
  n sublist `absChg xdesc deltaTable
 }

/ Find new entries (in current but not in previous)
/ Args:
/   current: table
/   previous: table
/   keyCols: symbol list
/ Returns: rows from current with no match in previous
newEntries:{[current; previous; keyCols]
  prevKeys:distinct keyCols#previous;
  curKeys:keyCols#current;
  mask:not (value flip curKeys) in\: value flip prevKeys;
  / Simpler approach: anti-join
  current where not ({x in y}'). flip (keyCols#current; keyCols#previous)
 }

/ Simpler new entries using except logic
newEntries:{[current; previous; keyCols]
  pKeys:?[previous; (); 1b; {x!x} keyCols];
  current lj pKeys;
  / Actually use a left join flag approach
  prevMarked:update __inPrev:1b from ?[previous; (); 0b; {x!x} keyCols];
  prevMarked:distinct prevMarked;
  joined:current lj keyCols xkey prevMarked;
  result:select from joined where null __inPrev;
  ![result; (); 0b; enlist `__inPrev]
 }

/ Find dropped entries (in previous but not in current)
/ Args: same as newEntries but reversed
droppedEntries:{[current; previous; keyCols]
  newEntries[previous; current; keyCols]
 }

/ ============================================================================
/ INTERNAL
/ ============================================================================

/ Rename metric columns with a suffix
/ Args: data (table), metricCols (symbol list), suffix (string)
/ Returns: table with renamed columns
renameMetrics:{[data; metricCols; suffix]
  oldNames:metricCols;
  newNames:`$string[metricCols],\:suffix;
  oldNames!newNames xcol data
 }

\d .
