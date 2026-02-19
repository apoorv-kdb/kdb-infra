/ temporal_join.q
/ As-of and window joins for temporal data
/ Stateless: table in, table out

/ As-of join: for each row in left, get most recent match from right
/ Args:
/   left: table - must have dateCol
/   right: table - must have dateCol
/   dateCol: symbol - date column used for as-of logic
/   keyCols: symbol list - exact match columns (can be empty `$())
/   valueCols: symbol list - columns to bring from right
/ Returns: left table enriched with valueCols from right
.temporal.asof:{[left; right; dateCol; keyCols; valueCols]
  if[0h = type keyCols; keyCols:`$()];
  rightSorted:`date xasc right;
  leftSorted:`date xasc left;

  / Build aj columns: keyCols then dateCol
  ajCols:$[0 = count keyCols; enlist dateCol; keyCols , dateCol];
  rightSubset:(ajCols , valueCols)#rightSorted;

  aj[ajCols; leftSorted; rightSubset]
 }

/ Window join: aggregate right-table rows within a time window of each left row
/ Args:
/   left: table
/   right: table
/   dateCol: symbol - date column
/   keyCols: symbol list - exact match columns
/   window: int - lookback days
/   valueCol: symbol - column to aggregate from right
/   aggFn: function - aggregation (sum, avg, count, etc.)
/   outCol: symbol - output column name
/ Returns: left table with outCol added
.temporal.windowJoin:{[left; right; dateCol; keyCols; window; valueCol; aggFn; outCol]
  / For each left row, find matching right rows within window
  result:{[right; dateCol; keyCols; window; valueCol; aggFn; leftRow]
    dt:leftRow dateCol;
    startDt:dt - window;

    / Filter right table
    subset:select from right where (dateCol#right)[dateCol] within (startDt; dt);

    / Apply key filters
    if[0 < count keyCols;
      subset:{[subset; col; val]
        select from subset where (col#subset)[col] = val
      }/[subset; keyCols; leftRow keyCols]];

    / Aggregate
    $[0 = count subset; 0n; aggFn subset[valueCol]]
  }[right; dateCol; keyCols; window; valueCol; aggFn] each 0!left;

  ![left; (); 0b; (enlist outCol)!(enlist result)]
 }

/ Point-in-time join: get the exact value at each date (no forward-looking)
/ Same as asof but enforces strict <= (not <)
.temporal.pit:{[left; right; dateCol; keyCols; valueCols]
  .temporal.asof[left; right; dateCol; keyCols; valueCols]
 }
