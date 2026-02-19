/ comparison.q
/ Period-over-period comparison (DoD, MoM, custom)
/ Stateless: table in, table out

/ Helper: rename columns with a suffix
.comparison.renameCols:{[tbl; cols; suffix]
  mapping:cols!{`$string[x],y}[;suffix] each cols;
  mapping xcol tbl
 }

/ Compute delta between two snapshots
/ Args:
/   data: table with date column
/   dateCol: symbol - date column name
/   currentDt: date - current period
/   previousDt: date - prior period
/   keyCols: symbol or symbol list - columns that identify a row
/   metricCols: symbol list - columns to compute deltas on
/ Returns: table with _current, _previous, _delta, _pctChange for each metric
.comparison.delta:{[data; dateCol; currentDt; previousDt; keyCols; metricCols]
  if[-11h = type keyCols; keyCols:enlist keyCols];

  current:?[data; enlist (=; dateCol; currentDt); 0b; ()];
  previous:?[data; enlist (=; dateCol; previousDt); 0b; ()];

  / Rename metric columns for each period
  curRenamed:.comparison.renameCols[current; metricCols; "_current"];
  prevRenamed:.comparison.renameCols[previous; metricCols; "_previous"];

  / Join on key columns
  joined:curRenamed lj keyCols xkey prevRenamed;

  / Compute deltas and pct changes
  {[joined; met]
    curCol:`$string[met],"_current";
    prevCol:`$string[met],"_previous";
    deltaCol:`$string[met],"_delta";
    pctCol:`$string[met],"_pctChange";

    joined:![joined; (); 0b; (enlist deltaCol)!(enlist (-; curCol; prevCol))];
    joined:![joined; (); 0b; (enlist pctCol)!(enlist {$[0 = y; 0n; (x - y) % abs y]}'[curCol; prevCol])];
    joined
  }/[joined; metricCols]
 }

/ ============================================================================
/ CONVENIENCE
/ ============================================================================

/ Day-over-day using a dates list
.comparison.dod:{[data; dates; dt; keyCols; metricCols]
  prevDt:.dates.prev[dates; dt];
  if[null prevDt; :([] info:enlist "No previous date available")];
  .comparison.delta[data; `date; dt; prevDt; keyCols; metricCols]
 }

/ Month-over-month (same day last month, or closest prior)
.comparison.mom:{[data; dates; dt; keyCols; metricCols]
  targetMonth:`month$dt - 31;
  monthDates:dates where (`month$dates) = targetMonth;
  if[0 = count monthDates; :([] info:enlist "No prior month data available")];
  prevDt:last monthDates;
  .comparison.delta[data; `date; dt; prevDt; keyCols; metricCols]
 }
