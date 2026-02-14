/ rolling.q
/ Windowed statistics on time series data
/ Moving average, standard deviation, sum, min, max over configurable windows
/
/ All functions expect data sorted by date. If grouping is needed
/ (e.g. rolling avg per business), use the *By variants.
/
/ Stateless: table in, table out

\d .rolling

/ ============================================================================
/ CORE WINDOW FUNCTIONS
/ ============================================================================

/ Moving average
/ Args: vals (numeric list), window (int)
/ Returns: float list (nulls for incomplete windows)
avg:{[vals; window]
  n:count vals;
  $[window > n; n#0Nf;
    {[w; v; i] $[i < w - 1; 0Nf; avg (neg w)#(i+1)#v]}[window; vals] each til n]
 }

/ Moving sum
movSum:{[vals; window]
  n:count vals;
  $[window > n; n#0Nf;
    {[w; v; i] $[i < w - 1; 0Nf; sum (neg w)#(i+1)#v]}[window; vals] each til n]
 }

/ Moving standard deviation
movStd:{[vals; window]
  n:count vals;
  $[window > n; n#0Nf;
    {[w; v; i] $[i < w - 1; 0Nf; dev (neg w)#(i+1)#v]}[window; vals] each til n]
 }

/ Moving min
movMin:{[vals; window]
  n:count vals;
  $[window > n; n#0Nf;
    {[w; v; i] $[i < w - 1; 0Nf; min (neg w)#(i+1)#v]}[window; vals] each til n]
 }

/ Moving max
movMax:{[vals; window]
  n:count vals;
  $[window > n; n#0Nf;
    {[w; v; i] $[i < w - 1; 0Nf; max (neg w)#(i+1)#v]}[window; vals] each til n]
 }

/ Moving median
movMedian:{[vals; window]
  n:count vals;
  $[window > n; n#0Nf;
    {[w; v; i] $[i < w - 1; 0Nf; med (neg w)#(i+1)#v]}[window; vals] each til n]
 }

/ ============================================================================
/ TABLE OPERATIONS
/ ============================================================================

/ Add a rolling statistic column to a table
/ Data must be sorted by date
/ Args:
/   data: table (sorted by date)
/   col: symbol - column to compute over
/   window: int - window size in rows
/   fn: symbol - one of `avg`sum`std`min`max`median
/   newCol: symbol - name for the new column
/ Returns: table with new column appended
addRolling:{[data; col; window; fn; newCol]
  vals:data col;
  result:$[fn;
    `avg;    .rolling.avg[vals; window];
    `sum;    movSum[vals; window];
    `std;    movStd[vals; window];
    `min;    movMin[vals; window];
    `max;    movMax[vals; window];
    `median; movMedian[vals; window];
    '"Unknown rolling function: ",string fn];
  ![data; (); 0b; (enlist newCol)!(enlist result)]
 }

/ Add multiple rolling statistics at once
/ Args:
/   data: table (sorted by date)
/   specs: list of dicts, each with `col`window`fn`newCol
/ Returns: table with all new columns appended
addMultiple:{[data; specs]
  {[d; spec]
    addRolling[d; spec`col; spec`window; spec`fn; spec`newCol]
  }/[data; specs]
 }

/ ============================================================================
/ GROUPED OPERATIONS
/ ============================================================================

/ Add a rolling statistic within groups
/ Sorts each group by date, computes rolling, reassembles
/ Args:
/   data: table
/   groupCols: symbol list - columns to group by (e.g. `business`product)
/   col: symbol - column to compute over
/   window: int - window size
/   fn: symbol - rolling function name
/   newCol: symbol - name for new column
/ Returns: table with new column (same row order as input)
addRollingBy:{[data; groupCols; col; window; fn; newCol]
  / Add original index to preserve order
  data:update __idx:i from data;

  / Group, sort each by date, compute rolling, reassemble
  groups:?[data; (); {x!x} groupCols; (enlist `rows)!(enlist (ungroup; (enlist; til; (count; `i))))];

  result:raze {[data; col; window; fn; newCol; grp]
    subset:`date xasc data grp`rows;
    addRolling[subset; col; window; fn; newCol]
  }[data; col; window; fn; newCol] each 0!groups;

  / Restore original order
  result:`__idx xasc result;
  ![result; (); 0b; enlist `__idx]
 }

/ ============================================================================
/ CONVENIENCE
/ ============================================================================

/ Common rolling specs builder
/ Args:
/   col: symbol - column to compute over
/   window: int - window size
/ Returns: list of spec dicts for avg, std, min, max
standardSpecs:{[col; window]
  prefix:string[col],"_",string[window],"d_";
  (`col`window`fn`newCol!(col; window; `avg; `$prefix,"avg");
   `col`window`fn`newCol!(col; window; `std; `$prefix,"std");
   `col`window`fn`newCol!(col; window; `min; `$prefix,"min");
   `col`window`fn`newCol!(col; window; `max; `$prefix,"max"))
 }

\d .
